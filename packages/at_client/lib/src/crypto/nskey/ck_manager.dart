import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart' show CryptoRuntime;
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:at_client/src/crypto/nskey/start_up_seeding.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show
        ckConveyanceMarker,
        ckSiblingCopyKey,
        currentCkPointerRecordName,
        parseCkConveyanceKey;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show visibleForTesting;

final _logger = AtSignLogger('CkManager');

/// How long a superseded content key is kept, by default, once the key that
/// replaced it was cut: the longest an atServer keeps a notification.
const Duration defaultSupersededCkGrace = Duration(days: 8);

/// Collects unused content keys once [sync] reports this client caught up,
/// with whichever manager [manager] names by then, and again at each later
/// catch-up while a pass is refused because writes arrived in between.
///
/// A service that stops first ends the wait, and nothing is collected.
Future<void> collectUnusedOnceCaughtUp(SyncService sync,
    CkManager? Function() manager, CryptoContext context) async {
  while (true) {
    try {
      await sync.waitUntilCaughtUp();
    } on StoppedException {
      return;
    }
    if (await _ranOrGaveUp(manager(), context)) return;
  }
}

/// One collection pass: false when it was refused because sync had not caught
/// up, true when it ran or failed in a way a retry would not change.
Future<bool> _ranOrGaveUp(CkManager? manager, CryptoContext context) async {
  if (manager == null) return true;
  try {
    return await manager.tryCollect(context) != null;
  } on StoppedException {
    return true;
  } catch (e) {
    _logger.warning('Could not collect unused content keys; the next start '
        'tries again: $e');
    return true;
  }
}

/// Keeps a current content key in place for each destination a client writes to.
///
/// Content keys are scoped per recipient, and minting one writes a conveyance
/// record, which cannot happen inside `encrypt` — so this runs before the put
/// pipeline starts, via [CryptoProvider.prepareForWrite].
class CkManager {
  final ContentKeyCache cache;
  final NskeyKeyRing keyRing;

  /// Finds which level of a nested namespace holds the nskey to seal to, shared
  /// with the data provider so both ends of a write agree on where it lives.
  final NskeyResolver resolver;

  /// Remembers which CK is current for each destination, so a cold write
  /// resumes it rather than cutting another. Null disables that: every cold
  /// write then mints, leaving a permanent conveyance record behind each time.
  final CurrentCkPointer? pointer;

  /// Which of a destination's advertised KEM keys this client is willing to
  /// seal to, strongest first. Defaults to everything this build can seal
  /// under; a narrowed list is a deployment choosing to refuse.
  final List<String> sealsToKeyAlgorithms;

  /// Asked, on the write path, whether the current content key should be
  /// replaced before anything else is written under it.
  final CkRotationPolicy ckRotationPolicy;

  /// How long a superseded content key is kept after the key that replaced it
  /// was cut, even when nothing in local storage cites it.
  ///
  /// A recipient may still need it for something only the recipient holds: a
  /// notification it has yet to open, or its cached copy of a shared value.
  final Duration supersededCkGrace;

  /// Asked, before a content key is conveyed to a namespace key this atSign
  /// owns, whether that namespace key should be replaced first.
  ///
  /// Null asks nothing, and the answer says whether a replacement happened, so
  /// the caller knows to re-resolve.
  Future<bool> Function(String namespace)? rotateOwnNamespaceKeyIfAsked;

  /// The client's start-up seeding, which a write that finds no namespace key
  /// waits on while it is still to come. Null waits for nothing.
  StartUpSeeding? startUpSeeding;

  CkManager(
      {required this.cache,
      required this.keyRing,
      NskeyResolver? resolver,
      this.sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos,
      this.ckRotationPolicy = rotateCkAfterOneYear,
      this.supersededCkGrace = defaultSupersededCkGrace,
      this.pointer = const CurrentCkPointer()})
      : resolver = resolver ??
            NskeyResolver(keyRing, sealsToKeyAlgorithms: sealsToKeyAlgorithms);

  /// Ensure `(destination, namespace)` has a current CK sealed to the
  /// destination's live nskey generation, minting and conveying one if not.
  ///
  /// The destination's advertised generation is resolved on every call — from
  /// the key ring's cache while that is fresh — and compared with the one the
  /// current CK was conveyed to: a sender never sees a recipient's
  /// decapsulation fail, so that comparison is the only way it learns of a
  /// rotation. A shared CK is also compared with the sender's own generation,
  /// since its sibling copy is sealed there: a revocation on either atSign
  /// rotates the namespace keys of that atSign the revoked enrollment held,
  /// and either generation moving cuts a fresh CK, whatever
  /// [ckRotationPolicy] would say.
  ///
  /// Cuts are serialised within this manager only: two processes of one
  /// enrollment writing at once can each cut a key, and the pointer keeps
  /// whichever was recorded last.
  ///
  /// A share is sealed to the recipient's key at the most specific level of
  /// [valueKey]'s name the recipient advertises one at
  /// ([NskeyResolver.resolveShare]), or with [sealToNamespace] at that
  /// namespace alone; what this client holds does not enter into it, and a
  /// share does not wait for start-up. [sealToNamespace] is refused for a
  /// write to this client's own atSign, and for a namespace [valueKey]'s name
  /// does not end with after a dot.
  ///
  /// When a write to this client's own atSign finds no key published and
  /// [startUpSeeding] is still to seed a namespace covering [valueKey], it
  /// waits for that seeding, at most [StartUpSeeding.wait], and resolves
  /// again. It waits the same way when the key it found is broader than a
  /// namespace start-up has said it will seed covering [valueKey]. When it
  /// holds no private for its key and start-up is asking for one, it waits
  /// for that ask and its answer before cutting a content key, within
  /// [StartUpSeeding.wait] of the write's start, so other writes' cuts never
  /// queue behind the wait.
  ///
  /// Returns the level this write starts at, which for a share is the value's
  /// own namespace as [NskeyResolver.startLevelOf] widens it, and the
  /// namespace of the content key it is to be sealed under, or null for a key
  /// with no owner or namespace.
  Future<({String namespace, String ckNs})?> ensureCurrent(
      CryptoContext context, AtKey valueKey,
      {bool? useRemoteAtServer, String? sealToNamespace}) async {
    final owner = valueKey.sharedWith ?? valueKey.sharedBy;
    if (owner == null || owner.isEmpty || valueKey.namespace == null) {
      if (sealToNamespace != null) {
        throw ArgumentError.value(
            sealToNamespace,
            'sealToNamespace',
            'applies only to a key with an owner and a namespace, and '
                '${valueKey.key} has ${owner == null || owner.isEmpty ? 'no owner' : 'no namespace'}');
      }
      return null;
    }
    final until = StartUpSeeding.boundFromNow();
    final holder = context.atClient.getCurrentAtSign();
    final sharing = _isShare(owner, holder);
    if (sealToNamespace != null) {
      _refuseUnlessSealable(valueKey, sealToNamespace, sharing: sharing);
    }
    final found = sharing
        ? await _shareKey(owner, valueKey, sealToNamespace)
        : await _ownKey(holder, owner, valueKey);
    final namespace = found.namespace;
    final advertised = found.advertised;
    if (advertised == null) {
      // NOTE: failing in this pre-pass is what keeps a cold start recoverable —
      // the caller can still route the write to legacy, which it could not do
      // mid-pipeline.
      throw NamespaceKeyUnavailableException(owner, namespace);
    }
    final ckNs = advertised.namespace;
    final chosen = (
      namespace:
          sharing ? await resolver.startLevelOf(holder, valueKey) : namespace,
      ckNs: ckNs,
    );
    final ownGeneration =
        await _ownGenerationHeld(context, owner, ckNs, valueKey);
    final current = cache.current(owner, ckNs);
    if (current != null &&
        cache.currentNskeyKid(owner, ckNs) == advertised.nskeyKid) {
      if (ownGeneration != null &&
          ownGeneration != cache.currentOwnNskeyKid(owner, ckNs)) {
        _logger.info('This enrollment now holds its own namespace key '
            '$ownGeneration covering $ckNs, which the content key '
            '${current.ckKid} shared with $owner is not sealed to, so a fresh '
            'one is cut');
      } else {
        // NOTE: with no recorded cut time the policy is not asked at all,
        // rather than told the key is fresh.
        final cutAt = cache.currentCutAt(owner, ckNs);
        if (cutAt == null) return chosen;
        final replace = await ckRotationPolicy(CkRotationContext(
          destination: owner,
          namespace: ckNs,
          ckKid: current.ckKid,
          cutAt: cutAt,
          now: DateTime.now().toUtc(),
        ));
        if (!replace) return chosen;
        _logger.info('The rotation policy asked for a fresh content key for '
            '$owner:$ckNs, replacing ${current.ckKid} cut at $cutAt');
      }
    }

    if (current == null) {
      final resumed = await _resumeCurrent(
          context, valueKey, owner, ckNs, advertised.nskeyKid, ownGeneration);
      if (resumed) return chosen;
    }

    var target = advertised;
    final rotate = rotateOwnNamespaceKeyIfAsked;
    if (rotate != null && owner == context.atClient.getCurrentAtSign()) {
      if (await rotate(ckNs)) {
        // NOTE: the rotation published a new generation; sealing to the one
        // read before it would convey to a key this atSign has moved off.
        final refreshed = await resolver.resolve(owner, ckNs);
        if (refreshed != null) target = refreshed;
      }
    }

    if (!sharing) {
      await _awaitOwnPrivate(owner, ckNs, target.alg, until: until);
    }
    await _cutAndConvey(context, valueKey, owner, ckNs, target.nskeyKid,
        keyAlgo: target.alg,
        useRemoteAtServer: useRemoteAtServer,
        replacing: current?.ckKid,
        ownGeneration: ownGeneration);
    return chosen;
  }

  /// Waits until [until], before the cut takes its turn, for start-up's ask
  /// for the private of [owner]'s own generation a cut in [ckNs] seals to
  /// under [keyAlgo], and throws as sealing would when it is still not held,
  /// so no cut waits while holding the turn.
  Future<void> _awaitOwnPrivate(String owner, String ckNs, String keyAlgo,
      {required DateTime until}) async {
    final usable =
        (await keyRing.currentPublic(owner, ckNs))?.usableFor([keyAlgo]);
    if (usable == null) return;
    if (await heldOwnAfterStartUpAsk(keyRing, owner, ckNs, usable.kid,
            until: until) ==
        null) {
      throw NskeyPrivateNotHeldException(owner, ckNs, usable.kid);
    }
  }

  /// Rotates the content key for the destination [valueKey] addresses: cuts a
  /// fresh CK, conveys it, and makes it what new writes encrypt under.
  ///
  /// [deleteSuperseded] deletes the record carrying the old CK, so nothing can
  /// unwrap it again and data written under it becomes undecryptable by design.
  /// It is off by default, because retaining that record is what lets a
  /// late-joining enrollment read history. A client that already decapsulated
  /// the old CK keeps reading until it observes the deletion. The delete comes
  /// first and a failed one throws, so a rotation that did not deliver its
  /// forward secrecy never reports success.
  ///
  /// Returns the CK new writes now use.
  Future<ContentKey> rotateContentKey(
    CryptoContext context,
    AtKey valueKey, {
    bool deleteSuperseded = false,
    bool? useRemoteAtServer,
  }) async {
    final owner = valueKey.sharedWith ?? valueKey.sharedBy;
    if (owner == null || owner.isEmpty || valueKey.namespace == null) {
      throw AtKeyException(
          'cannot rotate a content key for a record with no owner or '
          'namespace: $valueKey');
    }
    final holder = context.atClient.getCurrentAtSign();
    final found = _isShare(owner, holder)
        ? await _shareKey(owner, valueKey, null)
        : await _rotationOwnKey(holder, owner, valueKey);
    final advertised = found.advertised;
    if (advertised == null) {
      throw NamespaceKeyUnavailableException(owner, found.namespace);
    }
    final ckNs = advertised.namespace;

    // NOTE: the pointer is consulted as well as the cache because the process
    // that cut the superseded CK may have been a different one.
    final superseded = cache.current(owner, ckNs)?.ckKid ??
        (await pointer?.read(context.atClient, owner, ckNs))?.ckKid;

    if (deleteSuperseded && superseded != null) {
      // NOTE: before the successor is cut. A stop or failure between the two
      // then leaves no current CK, which the next write repairs by cutting
      // one; the other order could leave the superseded record readable for
      // good.
      await _deleteConveyance(context, valueKey, owner, ckNs, superseded);
    }

    return _cutAndConvey(context, valueKey, owner, ckNs, advertised.nskeyKid,
        keyAlgo: advertised.alg,
        useRemoteAtServer: useRemoteAtServer,
        force: true);
  }

  /// Cuts a fresh CK for `(owner, ckNs)`, conveys it sealed to [nskeyKid], and
  /// promotes it to current.
  ///
  /// [replacing] is the CK the caller found current, or null when it found
  /// none. A cut queued behind another that already replaced it, with a key
  /// sealed to [nskeyKid] whose sibling copy rests on [ownGeneration] where
  /// the caller holds one, returns that key instead of cutting a second one,
  /// unless [force] asks for a fresh one regardless.
  Future<ContentKey> _cutAndConvey(
    CryptoContext context,
    AtKey valueKey,
    String owner,
    String ckNs,
    String nskeyKid, {
    required String keyAlgo,
    bool? useRemoteAtServer,
    String? replacing,
    String? ownGeneration,
    bool force = false,
  }) =>
      _inTurn(() async {
        final current = cache.current(owner, ckNs);
        if (!force &&
            current != null &&
            current.ckKid != replacing &&
            cache.currentNskeyKid(owner, ckNs) == nskeyKid &&
            (ownGeneration == null ||
                cache.currentOwnNskeyKid(owner, ckNs) == ownGeneration)) {
          return current;
        }
        return _cutAndConveyInTurn(context, valueKey, owner, ckNs, nskeyKid,
            keyAlgo: keyAlgo, useRemoteAtServer: useRemoteAtServer);
      });

  Future<ContentKey> _cutAndConveyInTurn(
    CryptoContext context,
    AtKey valueKey,
    String owner,
    String ckNs,
    String nskeyKid, {
    required String keyAlgo,
    bool? useRemoteAtServer,
  }) async {
    // NOTE: this must not recurse — the conveyance write routes to at/nskey,
    // which asks for no preparation of its own.
    final ck = ContentKey(_freshKeyBytes());
    await context.atClient.put(
      SymmetricAesGcmProvider.conveyanceKeyFor(valueKey, ck.ckKid, ckNs),
      ck.toBase64(),
      putRequestOptions: PutRequestOptions()
        ..cryptoProviderId =
            nskeyProviderIdFor(keyAlgo) ?? nskeyCryptoProviderId
        // NOTE: the value about to be written cites this record, so it must not
        // outrun it — a remote-only value with a local-first conveyance reaches
        // the recipient before its key does.
        ..useRemoteAtServer = useRemoteAtServer ?? false,
    );
    final ownNskeyKid = await _conveySiblingCopy(
        context, valueKey, owner, ckNs, ck,
        useRemoteAtServer: useRemoteAtServer ?? false);

    // NOTE: promoted only once the record is durable — a failed conveyance left
    // as the current key would make every later value cite a CK never sent.
    final replaced = cache.current(owner, ckNs) != null;
    cache.putAsCurrent(owner, ckNs, ck, nskeyKid, ownNskeyKid: ownNskeyKid);
    await pointer?.write(context.atClient, owner, ckNs, ck.ckKid, nskeyKid,
        ownNskeyKid: ownNskeyKid);
    // NOTE: queued behind this cut and not awaited, so the write it serves is
    // not held up by a pass over local storage.
    if (replaced) unawaited(_collectAfterReplacing(context));
    return ck;
  }

  /// Collects now, or at the next sync that leaves this client caught up when
  /// the cut's own writes are still waiting to push.
  Future<void> _collectAfterReplacing(CryptoContext context) async {
    if (await _ranOrGaveUp(this, context)) return;
    final SyncService sync;
    try {
      sync = context.atClient.syncService;
    } on StateError {
      return;
    } on StoppedException {
      return;
    }
    await collectUnusedOnceCaughtUp(sync, () => this, context);
  }

  /// Deletes the conveyances of every content key this enrollment cut that is
  /// neither current nor cited by a record in local storage, and was
  /// superseded at least [supersededCkGrace] ago, and returns how many keys
  /// went.
  ///
  /// A key is superseded when this enrollment cuts the next key for the same
  /// destination and namespace; one with no successor counts from its own cut.
  /// Each conveyance records when its key was cut (`cutAt`); one written before
  /// it did counts from when this client stored it. A key still inside its
  /// grace goes at a later start or replacement.
  ///
  /// Asks local storage only where it answers completely — the client keeps
  /// one, no `syncRegex` narrows it, and sync has caught up — and otherwise
  /// deletes nothing; the passes the SDK runs itself, at a start and after a
  /// replacement, try again at the next sync that catches up. A client with no
  /// enrollment id names no cutter on what it conveys, so it deletes nothing.
  Future<int> collectUnused(CryptoContext context) async =>
      await tryCollect(context) ?? 0;

  /// [collectUnused], answering null when it was refused because sync had not
  /// caught up, the one refusal a later pass can overcome; a pass that does not
  /// look for another reason answers 0, as [collectUnused] does.
  ///
  /// Passes run one at a time, and one asked for while another waits to start
  /// joins it. A pass checks sync and scans local storage without holding up
  /// cuts, and takes their turn only to delete.
  ///
  /// Visible so a test can tell a pass sync refused from one that answered.
  @visibleForTesting
  Future<int?> tryCollect(CryptoContext context) {
    final waiting = _waitingPass;
    if (waiting != null) return waiting;
    final pass = _collecting.then((_) {
      _waitingPass = null;
      return _collectUnused(context);
    });
    _waitingPass = pass;
    _collecting = pass.then((_) {}, onError: (_) {});
    return pass;
  }

  /// The pass waiting to start, which a pass asked for meanwhile joins.
  Future<int?>? _waitingPass;

  /// Completes once every pass begun here so far has finished.
  Future<void> _collecting = Future<void>.value();

  Future<int?> _collectUnused(CryptoContext context) async {
    final atClient = context.atClient;
    final me = atClient.getCurrentAtSign()?.toLowerCase();
    final enrollmentId = atClient.enrollmentId;
    final store = atClient.getLocalSecondary()?.keyStore;
    if (me == null || enrollmentId == null || store == null) return 0;
    final partial = await _whyLocalStorageIsPartial(atClient);
    if (partial != null) {
      _logger.info('Not collecting unused content keys for $me: '
          '${partial.why}');
      return partial.transient ? null : 0;
    }

    final now = DateTime.now();
    final cut = <String, List<({String key, Map<String, dynamic> about})>>{};
    final cutAt = <String, DateTime>{};
    final current = <String>{...cache.currentKids};
    final cited = <String>{};
    final ownPointer =
        '.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}$me';
    await for (final key in await store.getKeys()) {
      final lower = key.toLowerCase();
      if (!lower.endsWith(me)) continue;
      if (lower.startsWith('$currentCkPointerRecordName.')) {
        if (lower.endsWith(ownPointer)) {
          final ckKid = _ckKidIn((await store.get(key))?.data);
          if (ckKid != null) current.add(ckKid);
        }
        continue;
      }
      final meta = await store.getMeta(key);
      final about = meta?.appMetadata?.additional;
      final ckKid = about?['ckKid'];
      if (ckKid is! String) continue;
      if (!key.contains(ckConveyanceMarker)) {
        cited.add(ckKid);
      } else if (about!['cutBy'] == enrollmentId) {
        (cut[ckKid] ??= []).add((key: key, about: about));
        final at = _cutAtOf(about) ?? meta!.createdAt ?? now;
        final earliest = cutAt[ckKid];
        if (earliest == null || at.isBefore(earliest)) cutAt[ckKid] = at;
      }
    }
    final supersededAt = _supersededAt(cut, cutAt);
    cut.removeWhere((ckKid, _) =>
        current.contains(ckKid) ||
        cited.contains(ckKid) ||
        now.difference(supersededAt[ckKid]!) < supersededCkGrace);
    if (cut.isEmpty) return 0;
    return _inTurn(() => _deleteUnlessCurrent(context, cut));
  }

  /// Deletes each of [cut]'s records and evicts its key, unless the key is
  /// current now or this enrollment's pointer for its scope names it, and
  /// returns how many keys went.
  ///
  /// Runs in turn, where no cut is half done, so a key a cut conveyed while
  /// the scan ran is current by now. Deletes from local storage, whatever the
  /// app's preference, and sync carries them to the atServer.
  Future<int> _deleteUnlessCurrent(CryptoContext context,
      Map<String, List<({String key, Map<String, dynamic> about})>> cut) async {
    final current = cache.currentKids;
    final kept = <String>{};
    for (final MapEntry(key: ckKid, value: records) in cut.entries) {
      final scope = _scopeOf(records.first.key, records.first.about);
      if (current.contains(ckKid) ||
          (scope != null && await _pointerNames(context, scope, ckKid))) {
        kept.add(ckKid);
      }
    }
    cut.removeWhere((ckKid, _) => kept.contains(ckKid));

    for (final MapEntry(key: ckKid, value: records) in cut.entries) {
      for (final record in records) {
        await context.atClient.delete(AtKey.fromString(record.key),
            deleteRequestOptions: DeleteRequestOptions()
              ..useRemoteAtServer = false);
        final scope = _scopeOf(record.key, record.about);
        if (scope != null) cache.evict(scope.owner, scope.ckNs, ckKid);
      }
    }
    if (cut.isNotEmpty) {
      _logger.info('Collected ${cut.length} content key(s) '
          '${context.atClient.enrollmentId} cut and nothing cites any more: '
          '${cut.keys.join(', ')}');
    }
    return cut.length;
  }

  /// Whether this enrollment's pointer for [scope], read from local storage,
  /// names [ckKid].
  Future<bool> _pointerNames(CryptoContext context,
      ({String owner, String ckNs}) scope, String ckKid) async {
    final key = pointer?.keyFor(context.atClient, scope.owner, scope.ckNs);
    final store = context.atClient.getLocalSecondary()?.keyStore;
    if (key == null || store == null) return false;
    return _ckKidIn((await store.get(key.toString()))?.data) == ckKid;
  }

  /// Why local storage cannot answer "does any record cite this key?"
  /// completely, and whether a later pass might, or null when it can.
  static Future<({String why, bool transient})?> _whyLocalStorageIsPartial(
      AtClient atClient) async {
    final syncRegex = atClient.getPreferences()?.syncRegex;
    if (syncRegex != null && syncRegex.isNotEmpty) {
      return (
        why: 'syncRegex "$syncRegex" narrows what local storage holds',
        transient: false
      );
    }
    try {
      if (!await atClient.syncService.isInSync()) {
        return (why: 'sync has not caught up', transient: true);
      }
    } on StoppedException {
      rethrow;
    } catch (e) {
      return (
        why: 'could not ask whether sync has caught up: $e',
        transient: true
      );
    }
    return null;
  }

  static String? _ckKidIn(String? pointer) {
    if (pointer == null) return null;
    try {
      final ckKid = jsonDecode(pointer)['ckKid'];
      return ckKid is String ? ckKid : null;
    } on FormatException {
      return null;
    }
  }

  /// When a conveyance says its key was cut, or null when it does not say.
  static DateTime? _cutAtOf(Map<String, dynamic> about) {
    final cutAt = about['cutAt'];
    return cutAt is String ? DateTime.tryParse(cutAt) : null;
  }

  /// When each of [cut] was superseded: the cut of the next key for the same
  /// scope, or its own cut when it has no successor.
  static Map<String, DateTime> _supersededAt(
      Map<String, List<({String key, Map<String, dynamic> about})>> cut,
      Map<String, DateTime> cutAt) {
    final byScope = <String, List<String>>{};
    for (final MapEntry(key: ckKid, value: records) in cut.entries) {
      final record = records.first;
      final scope = _scopeOf(record.key, record.about);
      final scopeId = scope == null ? ckKid : '${scope.owner}|${scope.ckNs}';
      (byScope[scopeId] ??= []).add(ckKid);
    }
    final supersededAt = <String, DateTime>{};
    for (final kids in byScope.values) {
      kids.sort((a, b) => cutAt[a]!.compareTo(cutAt[b]!));
      for (var i = 0; i < kids.length; i++) {
        supersededAt[kids[i]] = cutAt[kids[i < kids.length - 1 ? i + 1 : i]]!;
      }
    }
    return supersededAt;
  }

  /// The CK cache scope a conveyance record filed its key under.
  static ({String owner, String ckNs})? _scopeOf(
      String key, Map<String, dynamic> about) {
    final destination = about['destination'];
    final ckNs = about['ckNs'];
    if (destination is String && ckNs is String) {
      return (owner: destination, ckNs: ckNs);
    }
    final parsed = parseCkConveyanceKey(key);
    return parsed == null
        ? null
        : (owner: parsed.nskeyOwner, ckNs: parsed.ckNs);
  }

  Future<void> _turn = Future<void>.value();

  /// Completes once every cut and collection begun here so far has finished.
  @visibleForTesting
  Future<void> get idle async {
    await _collecting;
    await _turn;
  }

  /// Runs [work] once every cut and collection delete already begun here has
  /// finished, so a collection never deletes a key conveyed but not yet
  /// current.
  Future<T> _inTurn<T>(Future<T> Function() work) {
    final result = _turn.then((_) => work());
    _turn = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// The key a rotation of [valueKey]'s content key in this client's own
  /// atSign [owner] is sealed to, found from its start level with no wait.
  Future<({String namespace, ResolvedNskey? advertised})> _rotationOwnKey(
      String? holder, String owner, AtKey valueKey) async {
    final namespace = await resolver.startLevelOf(holder, valueKey);
    return (
      namespace: namespace,
      advertised: await resolver.resolve(owner, namespace)
    );
  }

  /// Whether a write whose owner is [owner], by a client of [holder], is a
  /// share: the owner is another atSign.
  static bool _isShare(String owner, String? holder) =>
      holder != null && owner.toAtsign() != holder.toAtsign();

  /// Throws unless [sealToNamespace] can apply to a write of [valueKey]: a
  /// share, whose key's name ends with it after a dot.
  static void _refuseUnlessSealable(AtKey valueKey, String sealToNamespace,
      {required bool sharing}) {
    if (!sharing) {
      throw ArgumentError.value(
          sealToNamespace,
          'sealToNamespace',
          'applies only to a share, and ${valueKey.key} is written to this '
              "client's own atSign");
    }
    if (!NskeyResolver.shareLevelsOf(valueKey)
        .contains(sealToNamespace.toLowerCase())) {
      throw ArgumentError.value(
          sealToNamespace,
          'sealToNamespace',
          'is not a namespace the name ${valueKey.key}.${valueKey.namespace} '
              'ends with');
    }
  }

  /// The recipient's key a share of [valueKey] to [owner] is sealed to, and
  /// the level its search started at: [sealToNamespace] alone when set, the
  /// most specific level of the key's name otherwise.
  Future<({String namespace, ResolvedNskey? advertised})> _shareKey(
      String owner, AtKey valueKey, String? sealToNamespace) async {
    if (sealToNamespace != null) {
      final namespace = sealToNamespace.toLowerCase();
      return (
        namespace: namespace,
        advertised: await resolver.resolveRequired(owner, namespace)
      );
    }
    final levels = NskeyResolver.shareLevelsOf(valueKey);
    return (
      namespace:
          levels.isEmpty ? valueKey.namespace!.toLowerCase() : levels.first,
      advertised: await resolver.resolveShare(owner, valueKey)
    );
  }

  /// The key a write of [valueKey] to this client's own atSign [owner] is
  /// sealed to, and the level its search started at, after waiting for
  /// [startUpSeeding] as [ensureCurrent] describes.
  Future<({String namespace, ResolvedNskey? advertised})> _ownKey(
      String? holder, String owner, AtKey valueKey) async {
    // NOTE: read before the search, so a seeding that ends during it is
    // searched for again rather than missed.
    final seeding = startUpSeeding?.isFinished == false;
    var namespace = await resolver.startLevelOf(holder, valueKey);

    var advertised = await resolver.resolve(owner, namespace);
    if (advertised == null) {
      final waited = seeding
          ? await _afterStartUpSeeding(holder, valueKey, namespace)
          : null;
      if (waited != null) {
        namespace = await resolver.startLevelOf(holder, valueKey);
        advertised = await resolver.resolve(owner, namespace);
        if (advertised == null) {
          final failure = startUpSeeding?.failureFor(waited.covering);
          if (failure != null) {
            throw NamespaceKeyUnavailableException(owner, waited.covering,
                because: 'this client\'s start-up could not publish it: '
                    '$failure');
          }
          if (waited.timedOut) {
            throw NamespaceKeyUnavailableException(owner, waited.covering,
                because: 'this client\'s start-up has not yet published it, '
                    '${waited.waited?.inSeconds} seconds after the write '
                    'began waiting; a later write succeeds once it is '
                    'published');
          }
        }
      } else {
        final failure = startUpSeeding?.failureFor(namespace);
        if (failure != null) {
          throw NamespaceKeyUnavailableException(owner, namespace,
              because: 'this client\'s start-up could not publish it: '
                  '$failure');
        }
      }
    } else if (seeding &&
        await _seedingBeyond(holder, valueKey, advertised.namespace)) {
      namespace = await resolver.startLevelOf(holder, valueKey);
      advertised = await resolver.resolve(owner, namespace);
    }
    return (namespace: namespace, advertised: advertised);
  }

  /// The namespace [startUpSeeding] seeds that covers [valueKey], once its
  /// seeding step has finished or [StartUpSeeding.wait] has passed, or null
  /// at once when it seeds none. `timedOut` says the wait passed first, after
  /// `waited`.
  Future<({String covering, bool timedOut, Duration? waited})?>
      _afterStartUpSeeding(
          String? holder, AtKey valueKey, String namespace) async {
    final seeding = startUpSeeding;
    if (seeding == null || holder == null) return null;
    try {
      final covering =
          await seeding.covering('${valueKey.key}.${valueKey.namespace}');
      return covering == null
          ? null
          : (covering: covering, timedOut: false, waited: null);
    } on TimeoutException catch (e) {
      return (
        covering: e.message ?? namespace,
        timedOut: true,
        waited: e.duration
      );
    }
  }

  /// Whether [startUpSeeding] was still to seed a namespace that covers
  /// [valueKey] more specifically than [found], and has since finished or run
  /// out of time, so the write resolves again.
  Future<bool> _seedingBeyond(
      String? holder, AtKey valueKey, String found) async {
    final seeding = startUpSeeding;
    if (seeding == null || holder == null) return false;
    try {
      return await seeding.coveringBeyond(
              '${valueKey.key}.${valueKey.namespace}', found) !=
          null;
    } on TimeoutException {
      return true;
    }
  }

  /// The level [sender]'s copy of a key it shares in [valueKey] is sealed
  /// at: the most specific namespace it holds a namespace private for that
  /// the key's whole name ends with after a dot, never a reserved one, or
  /// null when it holds none.
  ///
  /// Read from the namespaces this enrollment holds, so it asks nothing of the
  /// atServer.
  Future<String?> _ownLevel(String sender, AtKey valueKey) async {
    final name = '${valueKey.key}.${valueKey.namespace}'.toLowerCase();
    String? level;
    for (final held in await keyRing.heldNamespaces(sender)) {
      final namespace = held.toLowerCase();
      if (NskeyResolver.isReserved(namespace)) continue;
      if (name.endsWith('.$namespace') &&
          (level == null || namespace.length > level.length)) {
        level = namespace;
      }
    }
    return level;
  }

  /// Whether a key at [level] covers [ckNs]: is it, or a namespace it ends
  /// with after a dot.
  static bool _covers(String level, String ckNs) =>
      ckNs == level || ckNs.endsWith('.$level');

  /// The sender's own nskey generation at its own level for [valueKey] that a
  /// CK shared with [destination] in [ckNs] should now rest on: the
  /// advertised one, once this enrollment holds its private.
  ///
  /// Null for a CK that is not shared, when the sender holds no level covering
  /// both, and while the advertised generation's private has not reached this
  /// enrollment; a null never replaces a CK. Asking for the private is what
  /// pulls a generation this enrollment missed from its sibling enrollments.
  Future<String?> _ownGenerationHeld(CryptoContext context, String destination,
      String ckNs, AtKey valueKey) async {
    final sender = context.atClient.getCurrentAtSign();
    if (sender == null || !_isShare(destination, sender)) return null;
    try {
      final level = await _ownLevel(sender, valueKey);
      if (level == null || !_covers(level, ckNs)) return null;
      final own = await resolver.resolveAt(sender, level);
      if (own == null) return null;
      final held =
          await keyRing.privateHalf(sender, own.namespace, own.nskeyKid);
      return held == null ? null : own.nskeyKid;
    } on StoppedException {
      rethrow;
    } catch (e) {
      _logger.info('Could not tell which of its own namespace keys covering '
          '$ckNs $sender holds, so the content key it shares with '
          '$destination there is kept: $e');
      return null;
    }
  }

  /// Conveys [ck], shared with [destination], a second time — to this atSign's
  /// own key at its own level for [valueKey] — so its other enrollments, and
  /// this one after a restart, can open it, and returns the own generation it
  /// was sealed to.
  ///
  /// Sealed here and written as it is, because the put pipeline replaces the
  /// `appMetadata` that names the recipient; the record keeps the recipient's
  /// level [ckNs] in its name, and its `ns` names the level it was sealed to.
  /// Nothing is minted for it. The share goes without a copy, and this returns
  /// null, while this client's start-up has yet to publish a key covering
  /// [valueKey], when no namespace it holds covers [valueKey], and when the
  /// recipient's level is broader than this client's own. While the
  /// advertised generation's private has not reached this enrollment, the
  /// copy is sealed to the generation its keys in [ckNs] already rest on, or
  /// goes without one when none is recorded.
  Future<String?> _conveySiblingCopy(CryptoContext context, AtKey valueKey,
      String destination, String ckNs, ContentKey ck,
      {required bool useRemoteAtServer}) async {
    final sender = context.atClient.getCurrentAtSign();
    if (sender == null || !_isShare(destination, sender)) return null;
    final name = '${valueKey.key}.${valueKey.namespace}';
    final String? level;
    try {
      level = await _ownLevel(sender, valueKey);
    } on StoppedException {
      rethrow;
    } catch (e) {
      _logger.warning('Could not read which namespace keys $sender holds, so '
          'the content key ${ck.ckKid} shared with $destination has no sibling '
          'copy: $e');
      return null;
    }
    if (level == null) {
      _logger.warning(startUpSeeding?.isFinished == false
          ? '$sender\'s start-up has not yet published a namespace key '
              'covering $name, so the content key ${ck.ckKid} shared with '
              '$destination goes without a sibling copy; the first share after '
              'it has gets a fresh key with one'
          : 'No namespace key $sender holds covers $name, so the content key '
              '${ck.ckKid} shared with $destination has no sibling copy: no '
              'other enrollment of $sender can open what it shares, and this '
              'one cuts a fresh key after a restart');
      return null;
    }
    if (!_covers(level, ckNs)) {
      _logger.warning('$destination\'s key for $name is at $ckNs, broader '
          'than $sender\'s own level $level, so the content key ${ck.ckKid} '
          'shared with $destination has no sibling copy: no other enrollment '
          'of $sender can open what it shares, and this one cuts a fresh key '
          'after a restart');
      return null;
    }
    final own = await resolver.resolveAt(sender, level);
    if (own == null) {
      _logger.warning('$sender holds a namespace private for $level and '
          'advertises no key there, so the content key ${ck.ckKid} shared with '
          '$destination has no sibling copy');
      return null;
    }
    var alg = own.alg;
    String? sealTo;
    if (await keyRing.privateHalf(sender, own.namespace, own.nskeyKid) ==
        null) {
      final held = await _recordedOwnGeneration(
          context, sender, destination, ckNs, own.namespace);
      if (held == null) {
        _logger.warning('$sender holds no private for its namespace key '
            '${own.nskeyKid} covering $ckNs yet, and none of its content keys '
            'there rests on another, so the content key ${ck.ckKid} shared '
            'with $destination has no sibling copy until a fresh one is cut '
            'once that private arrives');
        return null;
      }
      _logger.info('$sender holds no private for its advertised namespace '
          'key ${own.nskeyKid} covering $ckNs yet, so the sibling copy of the '
          'content key ${ck.ckKid} shared with $destination is sealed to its '
          'generation ${held.kid}');
      alg = held.alg;
      sealTo = held.kid;
    }
    final key = ckSiblingCopyKey(sender: sender, ckKid: ck.ckKid, ckNs: ckNs)
      ..metadata.appMetadata = AppMetadata(
          providerId: nskeyProviderIdFor(alg) ?? nskeyCryptoProviderId,
          additional: {
            'destination': destination,
            'ns': own.namespace,
            if (sealTo != null) 'sealTo': sealTo,
          });
    final sealed =
        await CryptoRuntime(context.atClient).encryptForPut(key, ck.toBase64());
    await context.atClient.put(key, sealed,
        putRequestOptions: PutRequestOptions()
          ..shouldEncrypt = false
          ..alreadyEncrypted = true
          ..useRemoteAtServer = useRemoteAtServer);
    return key.metadata.appMetadata?.additional?['nskeyKid'] as String?;
  }

  /// The public half of the own generation this enrollment's content keys in
  /// [ckNs] already rest on and whose private it holds: the one toward
  /// [destination] first, from the cache or the pointer, then any other.
  Future<PackageKey?> _recordedOwnGeneration(CryptoContext context,
      String sender, String destination, String ckNs, String ownNs) async {
    final candidates = <String>{
      if (cache.currentOwnNskeyKid(destination, ckNs) case final kid?) kid,
      ...cache.currentOwnNskeyKidsIn(ckNs),
      if ((await pointer?.read(context.atClient, destination, ckNs))
              ?.ownNskeyKid
          case final kid?)
        kid,
    };
    for (final kid in candidates) {
      final held = await keyRing.heldPublic(sender, ownNs, kid);
      if (held != null) return held;
    }
    return null;
  }

  /// Deletes the conveyance records carrying [ckKid] — for a shared key, the
  /// recipient's and the sibling copy — and drops the key from this client's
  /// cache.
  ///
  /// Neither half is sufficient alone: the deletion stops anyone unwrapping the
  /// CK again, the eviction stops this client using the copy it already has.
  /// Another enrollment of this atSign evicts when it syncs the recipient's
  /// record going, whose name carries the recipient's scope.
  Future<void> _deleteConveyance(CryptoContext context, AtKey valueKey,
      String owner, String ckNs, String ckKid) async {
    await context.atClient.delete(
        SymmetricAesGcmProvider.conveyanceKeyFor(valueKey, ckKid, ckNs));
    final sender = context.atClient.getCurrentAtSign();
    if (sender != null && owner != sender) {
      await context.atClient
          .delete(ckSiblingCopyKey(sender: sender, ckKid: ckKid, ckNs: ckNs));
    }
    cache.evict(owner, ckNs, ckKid);
  }

  /// Re-adopts the CK this sender was last writing under for `(owner, ckNs)`,
  /// if the pointer names one, it is still sealed to [nskeyKid], and its
  /// sibling copy rests on [ownGeneration] whenever that is known.
  ///
  /// Returns whether the cache now holds a current CK. A pointer to a stale
  /// generation is ignored rather than repaired, so a fresh CK gets cut, and
  /// so is a pointer with no `ownNskeyKid` field.
  Future<bool> _resumeCurrent(CryptoContext context, AtKey valueKey,
      String owner, String ckNs, String nskeyKid, String? ownGeneration) async {
    final remembered = await pointer?.read(context.atClient, owner, ckNs);
    if (remembered == null ||
        remembered.nskeyKid != nskeyKid ||
        !remembered.ownRecorded ||
        (ownGeneration != null && remembered.ownNskeyKid != ownGeneration)) {
      return false;
    }

    // NOTE: reading the conveyance record routes back through the at/nskey
    // provider, which decapsulates and caches the CK as a side effect. The
    // atServer is asked when local storage has nothing, which is all an
    // ephemeral store ever has.
    final record = SymmetricAesGcmProvider.openableConveyanceKeyFor(
        valueKey, remembered.ckKid, ckNs, context.atClient.getCurrentAtSign());
    DateTime? conveyedAt;
    var opened = false;
    for (final remote in const [false, true]) {
      try {
        final read = await context.atClient.get(record,
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = remote);
        conveyedAt = read.metadata?.createdAt?.toUtc();
        opened = true;
        break;
      } on StoppedException {
        rethrow;
      } catch (e) {
        _logger.info('Could not open $record to resume content key '
            '${remembered.ckKid} for $owner:$ckNs (remote: $remote): $e');
      }
    }
    if (!opened) return false;

    final resumed = cache.get(owner, ckNs, remembered.ckKid);
    if (resumed == null) return false;
    cache.putAsCurrent(owner, ckNs, resumed, nskeyKid,
        ownNskeyKid: remembered.ownNskeyKid, cutAt: conveyedAt);
    return true;
  }

  static Uint8List _freshKeyBytes() =>
      Uint8List.fromList(base64Decode(AESKey.generate(32).key));
}
