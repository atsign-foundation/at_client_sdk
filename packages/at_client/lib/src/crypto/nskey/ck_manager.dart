import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:at_client/src/crypto/nskey/nskey_resolver.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

final _logger = AtSignLogger('CkManager');

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
  /// The destination's advertised generation is re-fetched on every call: a
  /// sender never sees a recipient's decapsulation fail, so that check is the
  /// only way it learns of a rotation.
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
  /// the old CK keeps reading until it observes the deletion.
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

    final ck = await _cutAndConvey(
        context, valueKey, owner, ckNs, advertised.nskeyKid,
        keyAlgo: advertised.alg, useRemoteAtServer: useRemoteAtServer);

    if (deleteSuperseded && superseded != null && superseded != ck.ckKid) {
      // NOTE: after the successor is durable, never before — a failure between
      // the two would leave the old CK deleted and no new one to write under.
      await _deleteConveyance(context, valueKey, owner, ckNs, superseded);
    }
    return ck;
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

    // NOTE: promoted only once the record is durable — a failed conveyance left
    // as the current key would make every later value cite a CK never sent.
    cache.putAsCurrent(owner, ckNs, ck, nskeyKid);
    await pointer?.write(context.atClient, owner, ckNs, ck.ckKid, nskeyKid);
    return ck;
  }

  /// Deletes the conveyance record carrying [ckKid] and drops the key from
  /// this client's cache.
  ///
  /// Neither half is sufficient alone: the deletion stops anyone unwrapping the
  /// CK again, the eviction stops this client using the copy it already has.
  Future<void> _deleteConveyance(CryptoContext context, AtKey valueKey,
      String owner, String ckNs, String ckKid) async {
    try {
      await context.atClient.delete(
          SymmetricAesGcmProvider.conveyanceKeyFor(valueKey, ckKid, ckNs));
      cache.evict(owner, ckNs, ckKid);
    } catch (e) {
      _logger.severe('Rotated the content key for $owner:$ckNs but could NOT '
          'delete the superseded conveyance $ckKid, so data written under it '
          'remains decryptable by anyone who can read that record — the '
          'forward secrecy this rotation was for has not been achieved: $e');
    }
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
    // provider, which decapsulates and caches the CK as a side effect.
    DateTime? conveyedAt;
    try {
      final record = await context.atClient.get(
          SymmetricAesGcmProvider.conveyanceKeyFor(
              valueKey, remembered.ckKid, ckNs));
      conveyedAt = record.metadata?.createdAt?.toUtc();
    } catch (e) {
      _logger.info('Could not resume content key ${remembered.ckKid} for '
          '$owner:$ckNs, so cutting a fresh one: $e');
      return false;
    }

    final resumed = cache.get(owner, ckNs, remembered.ckKid);
    if (resumed == null) return false;
    cache.putAsCurrent(owner, ckNs, resumed, nskeyKid, cutAt: conveyedAt);
    return true;
  }

  static Uint8List _freshKeyBytes() =>
      Uint8List.fromList(base64Decode(AESKey.generate(32).key));
}
