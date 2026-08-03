import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/nskey_resolver.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

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
final _logger = AtSignLogger('CkManager');

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

  CkManager(
      {required this.cache,
      required this.keyRing,
      NskeyResolver? resolver,
      this.pointer = const CurrentCkPointer()})
      : resolver = resolver ?? NskeyResolver(keyRing);

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
    //
    // The conveyance routes to at/nskey, whose encrypt seals the CK and caches
    // it. That write needs no preparation of its own, which is what stops this
    // recursing.
    final ck = ContentKey(_freshKeyBytes());
    await context.atClient.put(
      SymmetricAesGcmProvider.conveyanceKeyFor(valueKey, ck.ckKid, ckNs),
      ck.toBase64(),
      putRequestOptions: PutRequestOptions()
        ..cryptoProviderId = nskeyCryptoProviderId
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
    cache.putAsCurrent(owner, ckNs, ck, advertised.nskeyKid);
    await pointer?.write(
        context.atClient, owner, ckNs, ck.ckKid, advertised.nskeyKid);
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
