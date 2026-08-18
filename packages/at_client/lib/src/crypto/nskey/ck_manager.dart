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
/// Content keys are scoped **per recipient**, so the "no current CK" case is not
/// a one-off bootstrap — it fires the first time a client writes to any new
/// destination, and again whenever that destination rotates its nskey. This is
/// what makes `put` work at all: without it `at/symmetric/AES/GCM` has nothing
/// to encrypt under and refuses the write.
///
/// It lives above both providers deliberately. Minting a CK means *writing the
/// conveyance record*, and that cannot happen inside `encrypt` — by then the put
/// pipeline is mid-flight building a verb builder. So it runs as a preparation
/// step before the pipeline starts, via [CryptoProvider.prepareForWrite].
class CkManager {
  final ContentKeyCache cache;
  final NskeyKeyRing keyRing;

  /// Finds which level of a nested namespace holds the nskey to seal to. Shared
  /// with the data provider so both ends of a write agree on where the content
  /// key lives, and so the walk's miss-memory is warmed once rather than twice.
  final NskeyResolver resolver;

  /// Remembers which CK is current for each destination, so a cold write
  /// resumes it rather than cutting another. Null disables that — every cold
  /// write then mints, which is correct but leaves a permanent conveyance
  /// record behind each time.
  final CurrentCkPointer? pointer;

  /// Which of a destination's advertised KEM keys this client is willing to
  /// seal to, strongest first — `AtClientPreference.sealsToKeyAlgorithms`.
  ///
  /// Defaulted here, and only here, because a caller building a manager
  /// without a preference in hand has no basis to choose: everything this
  /// build can seal under refuses nobody, which is the behaviour a caller that
  /// said nothing meant. A client passes its preference's list, and a narrowed
  /// one is the deployment choosing to refuse.
  final List<String> sealsToKeyAlgorithms;

  CkManager(
      {required this.cache,
      required this.keyRing,
      NskeyResolver? resolver,
      this.sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos,
      this.pointer = const CurrentCkPointer()})
      : resolver = resolver ??
            NskeyResolver(keyRing, sealsToKeyAlgorithms: sealsToKeyAlgorithms);



  /// Ensure `(destination, namespace)` has a current CK sealed to the
  /// destination's *live* nskey generation, minting and conveying one if not.
  ///
  /// The re-fetch is the point, not an optimisation. A sender never sees a
  /// recipient's decapsulation fail, so an advertised-generation check here is
  /// the only way it learns of a rotation; without it a peer keeps sealing to a
  /// generation a revoked enrollment can still open, and revocation silently
  /// fails for everything inbound.
  Future<void> ensureCurrent(CryptoContext context, AtKey valueKey,
      {bool? useRemoteAtServer}) async {
    final owner = valueKey.sharedWith ?? valueKey.sharedBy;
    final namespace = valueKey.namespace;
    if (owner == null || owner.isEmpty || namespace == null) return;

    // Most-specific-first: a composed namespace resolves to whichever level
    // actually holds a key, and everything below is scoped to that level.
    final advertised = await resolver.resolve(owner, namespace);
    if (advertised == null) {
      // No level of the namespace has an nskey, so the destination has never
      // used or authorised it and there is nothing at the atSign level to fall
      // back to. Failing here, in the pre-pass, is what makes the cold start
      // recoverable: the caller has not yet committed to a scheme, so it can
      // still route the write to legacy if the app opted into that.
      // Discovering it mid-pipeline would leave only a hard failure.
      throw NamespaceKeyUnavailableException(owner, namespace);
    }
    final ckNs = advertised.namespace;
    final current = cache.current(owner, ckNs);
    if (current != null &&
        cache.currentNskeyKid(owner, ckNs) == advertised.nskeyKid) {
      return;
    }

    // Nothing cached — but this process may simply have restarted. Recovering
    // the CK it was already writing under, from the conveyance record it wrote
    // itself, is what stops every restart cutting a fresh key and leaving one
    // more record that can never be cleaned up.
    if (current == null) {
      final resumed = await _resumeCurrent(
          context, valueKey, owner, ckNs, advertised.nskeyKid);
      if (resumed) return;
    }

    // Either there is no CK for this destination, or the one we have was sealed
    // to a generation the destination has since rotated away from.
    await _cutAndConvey(context, valueKey, owner, ckNs, advertised.nskeyKid,
        keyAlgo: advertised.alg, useRemoteAtServer: useRemoteAtServer);
  }

  /// Rotates the content key for the destination [valueKey] addresses: cuts a
  /// fresh CK, conveys it, and makes it what new writes encrypt under.
  ///
  /// **The cheap forward-secrecy lever, and the only one that reaches data
  /// already written.** It is O(1) — one conveyance record, which every
  /// authorised client unwraps with the namespace nskey private it already
  /// holds — and it rides ordinary sync rather than the per-enrollment
  /// substrate. Rotating the nskey *keypair* is the other lever entirely: it
  /// costs one conveyance per enrollment, buys post-compromise security, and
  /// leaves every earlier CK readable. Conflating them is the mistake
  /// `design.md` §1.7 spends its first paragraph on.
  ///
  /// [deleteSuperseded] is the forward-secrecy knob, and **default off** is a
  /// deliberate policy rather than caution: retaining the superseded `__ck`
  /// record is what lets a late-joining enrollment read history, which is the
  /// legacy-like behaviour most apps expect. Turning it on deletes the record
  /// that carries the old CK, and from then on nothing can unwrap it — the
  /// nskey private cannot help, because no sealed copy of that CK survives.
  /// Data written under it becomes undecryptable **by design**.
  ///
  /// What it does not reach: a client that already decapsulated the old CK
  /// holds the plaintext key in memory or in its own cache, and only observing
  /// the deletion evicts it. So coarse forward secrecy is bounded by eviction
  /// *reachability* — a client that never resyncs keeps reading. The deletion
  /// is the trusted-computing base, not a guarantee about every device.
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
      // Nothing to seal the successor to. Distinct from the write path only in
      // that there is no legacy fallback to offer here — a rotation is not a
      // write the app can reroute.
      throw NamespaceKeyUnavailableException(owner, namespace);
    }
    final ckNs = advertised.namespace;

    // Read before the successor displaces it. The pointer is consulted as well
    // as the cache because the process that cut the superseded CK may have
    // been a different one — a rotation from a freshly started client would
    // otherwise supersede nothing and leave the old conveyance in place.
    final superseded = cache.current(owner, ckNs)?.ckKid ??
        (await pointer?.read(context.atClient, owner, ckNs))?.ckKid;

    final ck = await _cutAndConvey(
        context, valueKey, owner, ckNs, advertised.nskeyKid,
        keyAlgo: advertised.alg, useRemoteAtServer: useRemoteAtServer);

    if (deleteSuperseded && superseded != null && superseded != ck.ckKid) {
      // After the successor is durable, never before: a client whose write
      // failed between the two would otherwise be left with the old CK deleted
      // and no new one — every value written under the old key unreadable and
      // nothing to write the next one under.
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
    // The conveyance routes to at/nskey, whose encrypt seals the CK and caches
    // it. That write needs no preparation of its own, which is what stops this
    // recursing.
    final ck = ContentKey(_freshKeyBytes());
    await context.atClient.put(
      SymmetricAesGcmProvider.conveyanceKeyFor(valueKey, ck.ckKid, ckNs),
      ck.toBase64(),
      putRequestOptions: PutRequestOptions()
        // The destination's advertised KEM decides which conveyance provider
        // writes this, and the id is what routes the record back to the same
        // one on every future read.
        ..cryptoProviderId =
            nskeyProviderIdFor(keyAlgo) ?? nskeyCryptoProviderId
        // The value about to be written cites this record, so it must not
        // outrun it. A remote-only value paired with a local-first conveyance
        // reaches the recipient before its key does.
        ..useRemoteAtServer = useRemoteAtServer ?? false,
    );

    // Only now — the record carrying this CK is durable, so a reader can get
    // it. Promoting before the write returns would leave a failed conveyance
    // as the current key: the guard above would then skip conveying on every
    // retry, and every value written afterwards would cite a CK that was never
    // sent. The write throws on failure, so this is not reached.
    cache.putAsCurrent(owner, ckNs, ck, nskeyKid);
    await pointer?.write(context.atClient, owner, ckNs, ck.ckKid, nskeyKid);
    return ck;
  }

  /// Deletes the conveyance record carrying [ckKid] and drops the key from
  /// this client's cache.
  ///
  /// Both halves matter and neither is sufficient: deleting the record stops
  /// anyone unwrapping the CK again, and evicting stops *this* client from
  /// going on using the copy it has already unwrapped. Other clients evict when
  /// they observe the deletion syncing, which is what makes eviction a
  /// fleet-wide property rather than a local one.
  Future<void> _deleteConveyance(CryptoContext context, AtKey valueKey,
      String owner, String ckNs, String ckKid) async {
    try {
      await context.atClient.delete(
          SymmetricAesGcmProvider.conveyanceKeyFor(valueKey, ckKid, ckNs));
      cache.evict(owner, ckNs, ckKid);
    } catch (e) {
      // Loud: forward secrecy was asked for and not delivered. The successor
      // is in place, so writes are correct from here on — but the old key is
      // still unwrappable by anyone who can read the record, and a caller that
      // believes it rotated for FS has to know it did not.
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
  /// generation is ignored rather than repaired: the destination has rotated,
  /// so a fresh CK is exactly what should be cut.
  Future<bool> _resumeCurrent(CryptoContext context, AtKey valueKey,
      String owner, String ckNs, String nskeyKid) async {
    final remembered = await pointer?.read(context.atClient, owner, ckNs);
    if (remembered == null || remembered.nskeyKid != nskeyKid) return false;

    // Reading the conveyance record routes back through the at/nskey provider,
    // which decapsulates and caches the CK as a side effect.
    try {
      await context.atClient.get(SymmetricAesGcmProvider.conveyanceKeyFor(
          valueKey, remembered.ckKid, ckNs));
    } catch (e) {
      // The record is gone or will not open. Minting is the right answer, and
      // the caller does that next.
      _logger.info('Could not resume content key ${remembered.ckKid} for '
          '$owner:$ckNs, so cutting a fresh one: $e');
      return false;
    }

    final resumed = cache.get(owner, ckNs, remembered.ckKid);
    if (resumed == null) return false;
    cache.putAsCurrent(owner, ckNs, resumed, nskeyKid);
    return true;
  }

  static Uint8List _freshKeyBytes() =>
      Uint8List.fromList(base64Decode(AESKey.generate(32).key));
}
