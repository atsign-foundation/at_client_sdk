import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/at_reachability.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart' show CryptoRuntime;
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show
        ckConveyanceMarker,
        ckSiblingCopyKey,
        currentCkPointerRecordName,
        parseCkConveyanceKey;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show visibleForTesting;

final _logger = AtSignLogger('CkManager');

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
    return await manager._tryCollect(context) != null;
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

  /// Asked, before a content key is conveyed to a namespace key this atSign
  /// owns, whether that namespace key should be replaced first.
  ///
  /// Null asks nothing, and the answer says whether a replacement happened, so
  /// the caller knows to re-resolve.
  Future<bool> Function(String namespace)? rotateOwnNamespaceKeyIfAsked;

  CkManager(
      {required this.cache,
      required this.keyRing,
      NskeyResolver? resolver,
      this.sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos,
      this.ckRotationPolicy = rotateCkAfterOneWeek,
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
  /// rotation.
  Future<void> ensureCurrent(CryptoContext context, AtKey valueKey,
      {bool? useRemoteAtServer}) async {
    final owner = valueKey.sharedWith ?? valueKey.sharedBy;
    final namespace = valueKey.namespace;
    if (owner == null || owner.isEmpty || namespace == null) return;

    final advertised = await resolver.resolve(owner, namespace);
    if (advertised == null) {
      // NOTE: failing in this pre-pass is what keeps a cold start recoverable —
      // the caller can still route the write to legacy, which it could not do
      // mid-pipeline.
      throw NamespaceKeyUnavailableException(owner, namespace);
    }
    final ckNs = advertised.namespace;
    final current = cache.current(owner, ckNs);
    if (current != null &&
        cache.currentNskeyKid(owner, ckNs) == advertised.nskeyKid) {
      // NOTE: with no recorded cut time the policy is not asked at all, rather
      // than told the key is fresh.
      final cutAt = cache.currentCutAt(owner, ckNs);
      if (cutAt == null) return;
      final replace = await ckRotationPolicy(CkRotationContext(
        destination: owner,
        namespace: ckNs,
        ckKid: current.ckKid,
        cutAt: cutAt,
        now: DateTime.now().toUtc(),
      ));
      if (!replace) return;
      _logger.info('The rotation policy asked for a fresh content key for '
          '$owner:$ckNs, replacing ${current.ckKid} cut at $cutAt');
    }

    if (current == null) {
      final resumed = await _resumeCurrent(
          context, valueKey, owner, ckNs, advertised.nskeyKid);
      if (resumed) return;
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

    await _cutAndConvey(context, valueKey, owner, ckNs, target.nskeyKid,
        keyAlgo: target.alg, useRemoteAtServer: useRemoteAtServer);
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
    final namespace = valueKey.namespace;
    if (owner == null || owner.isEmpty || namespace == null) {
      throw AtKeyException(
          'cannot rotate a content key for a record with no owner or '
          'namespace: $valueKey');
    }

    final advertised = await resolver.resolve(owner, namespace);
    if (advertised == null) {
      throw NamespaceKeyUnavailableException(owner, namespace);
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
        keyAlgo: advertised.alg, useRemoteAtServer: useRemoteAtServer);
  }

  /// Cuts a fresh CK for `(owner, ckNs)`, conveys it sealed to [nskeyKid], and
  /// promotes it to current.
  Future<ContentKey> _cutAndConvey(
    CryptoContext context,
    AtKey valueKey,
    String owner,
    String ckNs,
    String nskeyKid, {
    required String keyAlgo,
    bool? useRemoteAtServer,
  }) =>
      _inTurn(() => _cutAndConveyInTurn(
          context, valueKey, owner, ckNs, nskeyKid,
          keyAlgo: keyAlgo, useRemoteAtServer: useRemoteAtServer));

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
    await _conveySiblingCopy(context, owner, ckNs, ck,
        useRemoteAtServer: useRemoteAtServer ?? false);

    // NOTE: promoted only once the record is durable — a failed conveyance left
    // as the current key would make every later value cite a CK never sent.
    final replaced = cache.current(owner, ckNs) != null;
    cache.putAsCurrent(owner, ckNs, ck, nskeyKid);
    await pointer?.write(context.atClient, owner, ckNs, ck.ckKid, nskeyKid);
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
    }
    await collectUnusedOnceCaughtUp(sync, () => this, context);
  }

  /// Deletes the conveyances of every content key this enrollment cut that is
  /// neither current nor cited by a record in local storage, and returns how
  /// many keys went.
  ///
  /// Asks local storage only where it answers completely — the client keeps
  /// one, no `syncRegex` narrows it, and sync has caught up — and otherwise
  /// deletes nothing; the passes the SDK runs itself, at a start and after a
  /// replacement, try again at the next sync that catches up. A client with no
  /// enrollment id names no cutter on what it conveys, so it deletes nothing.
  Future<int> collectUnused(CryptoContext context) async =>
      await _tryCollect(context) ?? 0;

  /// [collectUnused], answering null when it was refused because sync had not
  /// caught up, the one refusal a later pass can overcome.
  Future<int?> _tryCollect(CryptoContext context) =>
      _inTurn(() => _collectUnused(context));

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

    final cut = <String, List<({String key, Map<String, dynamic> about})>>{};
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
      final about = (await store.getMeta(key))?.appMetadata?.additional;
      final ckKid = about?['ckKid'];
      if (ckKid is! String) continue;
      if (!key.contains(ckConveyanceMarker)) {
        cited.add(ckKid);
      } else if (about!['cutBy'] == enrollmentId) {
        (cut[ckKid] ??= []).add((key: key, about: about));
      }
    }
    cut.removeWhere(
        (ckKid, _) => current.contains(ckKid) || cited.contains(ckKid));

    for (final MapEntry(key: ckKid, value: records) in cut.entries) {
      for (final record in records) {
        await context.atClient.delete(AtKey.fromString(record.key));
        final scope = _scopeOf(record.key, record.about);
        if (scope != null) cache.evict(scope.owner, scope.ckNs, ckKid);
      }
    }
    if (cut.isNotEmpty) {
      _logger.info('Collected ${cut.length} content key(s) $enrollmentId cut '
          'and nothing cites any more: ${cut.keys.join(', ')}');
    }
    return cut.length;
  }

  /// Why local storage cannot answer "does any record cite this key?"
  /// completely, and whether a later pass might, or null when it can.
  static Future<({String why, bool transient})?> _whyLocalStorageIsPartial(
      AtClient atClient) async {
    final preference = atClient.getPreferences();
    if (preference == null || !preference.isLocalStoreRequired) {
      return (why: 'this client keeps no local store', transient: false);
    }
    final syncRegex = preference.syncRegex;
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
  Future<void> get idle => _turn;

  /// Runs [work] once every cut and collection already begun here has
  /// finished, so a collection never sees a key conveyed but not yet current.
  Future<T> _inTurn<T>(Future<T> Function() work) {
    final result = _turn.then((_) => work());
    _turn = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Conveys [ck], shared with [destination], a second time — to this atSign's
  /// own key covering [ckNs] — so its other enrollments, and this one after a
  /// restart, can open it.
  ///
  /// Sealed here and written as it is, because the put pipeline replaces the
  /// `appMetadata` that names the recipient. An atSign holding no key covering
  /// [ckNs] mints one there first, at the recipient's level rather than the
  /// value's own; where it makes none, the share goes without a copy.
  Future<void> _conveySiblingCopy(
      CryptoContext context, String destination, String ckNs, ContentKey ck,
      {required bool useRemoteAtServer}) async {
    final sender = context.atClient.getCurrentAtSign();
    if (sender == null || destination == sender) return;
    var own = await resolver.resolve(sender, ckNs);
    if (own == null) {
      final reached = await context.atClient.ensureReachable(ckNs);
      if (reached.isReachable) own = await resolver.resolve(sender, ckNs);
      if (own == null) {
        _logger.warning('$sender holds no namespace key covering $ckNs and '
            'made none, because ${_whyNoKey(reached, ckNs)}, so the content '
            'key ${ck.ckKid} shared with $destination has no sibling copy: '
            'no other enrollment of $sender can open what it shares, and this '
            'one cuts a fresh key after a restart');
        return;
      }
    }
    final key = ckSiblingCopyKey(sender: sender, ckKid: ck.ckKid, ckNs: ckNs)
      ..metadata.appMetadata = AppMetadata(
          providerId: nskeyProviderIdFor(own.alg) ?? nskeyCryptoProviderId,
          additional: {'destination': destination, 'ns': own.namespace});
    final sealed =
        await CryptoRuntime(context.atClient).encryptForPut(key, ck.toBase64());
    await context.atClient.put(key, sealed,
        putRequestOptions: PutRequestOptions()
          ..shouldEncrypt = false
          ..useRemoteAtServer = useRemoteAtServer);
  }

  static String _whyNoKey(AtReachabilityResult reached, String ckNs) =>
      switch (reached.outcome) {
        AtReachability.postureDoesNotSeed => 'seedNamespaceKeys is off',
        AtReachability.noKeySource =>
          'this client has no key source to file one in',
        AtReachability.notAuthorised => '$ckNs can never hold a key',
        AtReachability.timedOut => 'minting one timed out',
        AtReachability.failed => 'minting one failed: ${reached.error}',
        AtReachability.alreadyReachable ||
        AtReachability.published =>
          'a key is published there that this client could not resolve',
      };

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
  /// if the pointer names one and it is still sealed to [nskeyKid].
  ///
  /// Returns whether the cache now holds a current CK. A pointer to a stale
  /// generation is ignored rather than repaired, so a fresh CK gets cut.
  Future<bool> _resumeCurrent(CryptoContext context, AtKey valueKey,
      String owner, String ckNs, String nskeyKid) async {
    final remembered = await pointer?.read(context.atClient, owner, ckNs);
    if (remembered == null || remembered.nskeyKid != nskeyKid) return false;

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
    cache.putAsCurrent(owner, ckNs, resumed, nskeyKid, cutAt: conveyedAt);
    return true;
  }

  static Uint8List _freshKeyBytes() =>
      Uint8List.fromList(base64Decode(AESKey.generate(32).key));
}
