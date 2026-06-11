import 'dart:async' show FutureOr, Timer;
import 'dart:convert' show base64Decode, jsonEncode;

import 'package:at_chops/at_chops.dart'
    show
        AtSigningInput,
        AtSigningMode,
        AtSigningResult,
        AtSigningVerificationInput,
        HashingAlgoType,
        SigningAlgoType;
import 'package:at_client/at_client.dart'
    show
        AtKey,
        AtValue,
        EnrollmentConstants,
        GetRequestOptions,
        IllegalStateException;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:meta/meta.dart' show visibleForTesting;

/// Wraps payloads in signed JSON envelopes, and verifies envelopes created by
/// other clients of the same or another atSign.
///
/// Envelopes are signed with this client's APKAM (PKAM) keypair — the keypair
/// whose public half [ApkamSigning] publishes at
/// `public:_apsk.<enrollmentId>.a.__e@atsign` — and carry the signer's
/// [ApkamSigning.enrollmentId] so that verifiers can fetch that key.
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
  FutureOr<Map<String, Object?>> wrapAndSign(
    Object? payload, {
    Object? Function(Object? nonEncodable)? toEncodable,
  }) {
    Map<String, Object?> envelope = {'payload': payload};

    String signableText;
    try {
      signableText = _signableText(payload, toEncodable: toEncodable);
    } catch (e, st) {
      logger.severe(
        "Failed to encode payload for signing (you may need to pass "
        "toEncodable to wrapAndSign): $e, $st",
      );
      rethrow;
    }

    // Sign with the APKAM (PKAM) keypair: its public half is what
    // [ApkamSigning.publishPublicSigningKey] publishes, so verifiers can
    // check the signature against the per-enrollment _apsk key.
    // (AtSigningMode.data would sign with the atSign-wide encryption keypair,
    // which is NOT the published key.)
    final AtSigningInput signingInput = AtSigningInput(signableText)
      ..signingMode = AtSigningMode.pkam;
    final AtSigningResult sr = atClient.atChops!.sign(signingInput);

    envelope['signature'] = sr.result.toString();
    envelope['hashingAlgo'] = sr.atSigningMetaData.hashingAlgoType!.name;
    envelope['signingAlgo'] = sr.atSigningMetaData.signingAlgoType!.name;
    envelope['enrollmentId'] = enrollmentId;
    return envelope;
  }

  /// Same as [wrapAndSign] but we also call jsonEncode for you :)
  FutureOr<String> wrapAndSignAndJsonEncode(
    Object? payload, {
    Object? Function(Object? nonEncodable)? toEncodable,
  }) async {
    Map<String, Object?> envelope =
        await wrapAndSign(payload, toEncodable: toEncodable);
    return jsonEncode(envelope, toEncodable: toEncodable);
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
  Future<void> verifyEnvelopeSignature(
    Map envelope, {
    required String signerAtSign,
  }) async {
    final String signature = envelope['signature'];
    final String signerEnrollmentId = envelope['enrollmentId'];
    final hashingAlgo = HashingAlgoType.values.byName(envelope['hashingAlgo']);
    final signingAlgo = SigningAlgoType.values.byName(envelope['signingAlgo']);
    final String signableText = _signableText(envelope['payload']);

    final pk = await getApkamPublicKey(signerAtSign, signerEnrollmentId);
    AtSigningVerificationInput input =
        AtSigningVerificationInput(signableText, base64Decode(signature), pk)
          ..signingMode = AtSigningMode.pkam
          ..signingAlgoType = signingAlgo
          ..hashingAlgoType = hashingAlgo;

    AtSigningResult svr = atClient.atChops!.verify(input);
    if (svr.result != true) {
      throw AtSigningVerificationException(
          'Signature verification failed using public key for '
          '$signerAtSign enrollment $signerEnrollmentId : $pk');
    }
  }

  /// The exact text that is signed and verified. Strings are signed as-is;
  /// everything else is signed as its json encoding. Verification re-derives
  /// this from the decoded envelope, which is stable because Dart maps
  /// preserve insertion order through a jsonEncode/jsonDecode round trip.
  String _signableText(
    Object? payload, {
    Object? Function(Object? nonEncodable)? toEncodable,
  }) {
    if (payload is String) {
      return payload;
    }
    return jsonEncode(payload, toEncodable: toEncodable);
  }

  /// Fetch the APKAM public signing key which [enrollmentId] of [atSign] has
  /// published in its per-enrollment namespace. See
  /// [ApkamSigning.publicSigningKeyUri].
  Future<String> getApkamPublicKey(String atSign, String enrollmentId) async {
    atSign = atSign.toAtsign();

    String? cached = lookupPubKey(atSign, enrollmentId);
    if (cached != null) return cached;

    var s = 'public:_apsk.$enrollmentId'
        '.${EnrollmentConstants.perEnrollmentApproved}'
        '$atSign';
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
