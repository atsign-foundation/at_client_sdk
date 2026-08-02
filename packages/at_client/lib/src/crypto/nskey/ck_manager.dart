import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_commons/at_commons.dart';

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

  CkManager({required this.cache, required this.keyRing});

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

    final advertised = await keyRing.currentPublic(owner, namespace);
    if (advertised == null) {
      // The destination has never used this namespace, so there is no nskey to
      // seal to. Cold-start sealing to public:pqpublickey is not wired yet;
      // leaving it alone lets the data provider raise the clearer error.
      return;
    }

    final current = cache.current(owner, namespace);
    if (current != null &&
        cache.currentNskeyKid(owner, namespace) == advertised.nskeyKid) {
      return;
    }

    // Either there is no CK for this destination, or the one we have was sealed
    // to a generation the destination has since rotated away from.
    //
    // The conveyance routes to at/nskey, whose encrypt seals the CK and caches
    // it. That write needs no preparation of its own, which is what stops this
    // recursing.
    final ck = ContentKey(_freshKeyBytes());
    await context.atClient.put(
      SymmetricAesGcmProvider.conveyanceKeyFor(valueKey, ck.ckKid),
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
    cache.putAsCurrent(owner, namespace, ck, advertised.nskeyKid);
  }

  static Uint8List _freshKeyBytes() =>
      Uint8List.fromList(base64Decode(AESKey.generate(32).key));
}
