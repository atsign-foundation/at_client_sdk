import 'dart:async' show FutureOr, Timer;
import 'dart:convert' show jsonEncode;

import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/signing/envelope_signature.dart'
    show apskUri, SignedEnvelope, signEnvelope, verifyEnvelope;
import 'package:at_commons/at_commons.dart'
    show AtKey, AtSigningVerificationException, AtValue, IllegalStateException;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// Wraps payloads in signed JSON envelopes, and verifies envelopes created by
/// other clients of the same or another atSign.
///
/// Envelopes are signed with this client's APKAM (PKAM) keypair — the keypair
/// whose public half [ApkamSigning] publishes at
/// `public:_apsk.<enrollmentId>.a.__e@atsign` — and carry the signer's
/// [ApkamSigning.enrollmentId] so that verifiers can fetch that key.
@experimental
mixin EnvelopeSigning on ApkamSigning {
  /// How to handle caching of public keys used for verification
  ///
  /// Set this value to null to disable caching.
  ///
  /// cacheExpiry: how long until the cached public key expires
  ///              (used for verification)
  ///
  /// resetOnLookup: Whether to reset the expiry timer when a lookup is made
  abstract final ({
    Duration cacheExpiry,
    bool resetOnLookup
  })? publicKeyCacheSettings;

  /// Create a json envelope around [payload] in a format that can be verified
  /// by [verifyEnvelopeSignature].
  ///
  /// [payload] must be a String or a json-encodable object.
  /// [toEncodable] is passed directly to [jsonEncode].
  /// Read the [jsonEncode] docs to learn how to use it.
  Future<SignedEnvelope> wrapAndSign(
    Object? payload, {
    Object? Function(Object? nonEncodable)? toEncodable,
  }) async {
    // Resolved before the try, not inside it: that catch reports a payload
    // that could not be encoded, and a keyfile read that fails is not one.
    final keys = await signingKeys;
    try {
      // Sign with the strongest key this enrollment holds, whose public half
      // is what [ApkamSigning.publishPublicSigningKey] publishes, so verifiers
      // can check the signature against the per-enrollment _apsk key. (Signing
      // with the atSign-wide encryption keypair would use a key that is NOT
      // the published one.) One signature: a signer emits one per active
      // signing key it holds, and the multi-signature writer is what turns
      // this into the whole set.
      return signEnvelope(
        payload,
        keys: keys.first,
        enrollmentId: enrollmentId,
        toEncodable: toEncodable,
      );
    } on Object catch (e, st) {
      logger.severe(
        "Failed to encode payload for signing (you may need to pass "
        "toEncodable to wrapAndSign): $e, $st",
      );
      rethrow;
    }
  }

  /// Same as [wrapAndSign] but we also call jsonEncode for you :)
  FutureOr<String> wrapAndSignAndJsonEncode(
    Object? payload, {
    Object? Function(Object? nonEncodable)? toEncodable,
  }) async {
    final envelope = await wrapAndSign(payload, toEncodable: toEncodable);
    // No toEncodable here: the payload was already encoded into base64url by
    // the signing, and what is left is strings.
    return jsonEncode(envelope.toJson());
  }

  /// Verify an envelope created by [wrapAndSign] or [wrapAndSignAndJsonEncode].
  ///
  /// The signature is verified against the APKAM public signing key which the
  /// signer's enrollment (the `enrollmentId` field of the envelope) has
  /// published at `public:_apsk.<enrollmentId>.a.__e<signerAtSign>`. Only the
  /// owning enrollment may write to that location, so a valid signature proves
  /// the envelope was created by a client of that (approved) enrollment.
  ///
  /// Throws an [Exception] on failed validation.
  /// [signerEnrollmentId] overrides the envelope's own `enrollmentId` claim as
  /// the address to fetch `_apsk` from. Supply it whenever something outside
  /// the envelope already establishes whose it is — an enrollment record, say
  /// — which is also the only way to verify an envelope that carries **no**
  /// claim. A key package signed before its enrollment existed is exactly
  /// that: the atServer had not assigned an id yet, so there was nothing
  /// truthful to stamp.
  Future<void> verifyEnvelopeSignature(
    SignedEnvelope envelope, {
    required String signerAtSign,
    String? signerEnrollmentId,
  }) async {
    final String? id = signerEnrollmentId ?? envelope.signerEnrollmentId;
    if (id == null) {
      throw AtSigningVerificationException(
          'Cannot verify an envelope that names no enrollment and was given '
          'none: there is no _apsk to check the signature against');
    }

    final pk = await getApkamPublicKey(signerAtSign, id);
    try {
      await verifyEnvelope(envelope, signerPublicKey: pk);
    } on AtSigningVerificationException {
      throw AtSigningVerificationException(
          'Signature verification failed using public key for '
          '$signerAtSign enrollment $id : $pk');
    }
  }

  /// Fetch the APKAM public signing key which [enrollmentId] of [atSign] has
  /// published in its per-enrollment namespace. See
  /// [ApkamSigning.publicSigningKeyUri].
  Future<String> getApkamPublicKey(String atSign, String enrollmentId) async {
    atSign = atSign.toAtsign();

    String? cached = lookupPubKey(atSign, enrollmentId);
    if (cached != null) return cached;

    var s = apskUri(atSign, enrollmentId);
    final AtValue av = await atClient.get(
      AtKey.fromString(s),
      getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
    );
    if (av.value is! String) {
      throw IllegalStateException('Value of $s is not a String');
    }

    cachePubKey(atSign, enrollmentId, av.value);

    return av.value;
  }

  // In memory caching of public keys (to reduce latency)

  @visibleForTesting
  final Map<String, (String, Timer)> pubKeyCache = {};

  String _cacheKey(String atSign, String enrollmentId) =>
      '$atSign#$enrollmentId';

  @visibleForTesting
  void cachePubKey(String atSign, String enrollmentId, String pubKey) {
    if (publicKeyCacheSettings == null) return;

    // Create a timer to auto purge the cache
    final timer = Timer(publicKeyCacheSettings!.cacheExpiry, () {
      pubKeyCache.remove(_cacheKey(atSign, enrollmentId));
    });
    pubKeyCache[_cacheKey(atSign, enrollmentId)] = (pubKey, timer);
  }

  @visibleForTesting
  String? lookupPubKey(String atSign, String enrollmentId) {
    if (publicKeyCacheSettings == null) return null;

    final cacheValue = pubKeyCache[_cacheKey(atSign, enrollmentId)];
    if (cacheValue == null) return null;

    if (publicKeyCacheSettings!.resetOnLookup) {
      // Cancel the existing timer and create a new one
      cacheValue.$2.cancel();
      final timer = Timer(publicKeyCacheSettings!.cacheExpiry, () {
        pubKeyCache.remove(_cacheKey(atSign, enrollmentId));
      });
      pubKeyCache[_cacheKey(atSign, enrollmentId)] = (cacheValue.$1, timer);
    }
    return cacheValue.$1;
  }
}
