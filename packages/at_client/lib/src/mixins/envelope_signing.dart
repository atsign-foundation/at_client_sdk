import 'dart:async' show FutureOr, Timer;
import 'dart:convert' show jsonEncode, base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show
        AtSigningInput,
        AtSigningMode,
        AtSigningResult,
        HashingAlgoType,
        AtSigningVerificationInput,
        SigningAlgoType;
import 'package:at_client/at_client.dart'
    show
        AtClient,
        AtKey,
        AtPublicKeyNotFoundException,
        AtValue,
        IllegalStateException;
import 'package:at_client/at_client_mixins.dart' show ApkamSigning;
import 'package:at_commons/at_commons.dart'
    show AtSigningVerificationException, AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show visibleForTesting;

// TODO(xavierchanth): write tests
mixin EnvelopeSigning on ApkamSigning {
  /// How to handle caching of public keys used for verification
  ///
  /// Set this value to null to disable caching.
  ///
  /// cacheExpiry: how long until the cached public key expires
  ///              (used for verification)
  ///
  /// refreshOnLookup: Whether to reset the expiry timer when a lookup is made
  abstract final ({
    Duration cacheExpiry,
    bool resetOnLookup
  })? publicKeyCacheSettings;

  /// Create a json envelope around [payload] in a format that can be verified
  /// by [verifyEnvelopeSignature].
  ///
  /// [toEncodable] is passed directly to [jsonEncode].
  /// Read the [jsonEncode] docs to learn how to use it.
  FutureOr<Map<String, Object?>> wrapAndSign(
    Object? payload, {
    Object? Function(Object? nonEncodable)? toEncodable,
  }) {
    Map<String, Object?> envelope = {'payload': payload};

    // Try to encode the type for signing
    if (payload is! String && payload is! Uint8List) {
      try {
        payload = jsonEncode(payload, toEncodable: toEncodable);
      } catch (e, st) {
        logger.severe(
          "Failed to encode payload for signing (you may need to pass "
          "toEncodable to wrapAndSign): $e, $st",
        );
        rethrow;
      }
    }

    final AtSigningInput signingInput = AtSigningInput(payload)
      ..signingMode = AtSigningMode.data;
    final AtSigningResult sr = atClient.atChops!.sign(signingInput);

    final String signature = sr.result.toString();
    envelope['signature'] = signature;
    envelope['hashingAlgo'] = sr.atSigningMetaData.hashingAlgoType!.name;
    envelope['signingAlgo'] = sr.atSigningMetaData.signingAlgoType!.name;
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
  /// throws an [Exception] on failed validation.
  FutureOr<void> verifyEnvelopeSignature(
    AtClient atClient,
    String requestingAtsign,
    AtSignLogger logger,
    Map envelope,
  ) async {
    final String signature = envelope['signature'];
    Map payload = envelope['payload'];
    final hashingAlgo = HashingAlgoType.values.byName(envelope['hashingAlgo']);
    final signingAlgo = SigningAlgoType.values.byName(envelope['signingAlgo']);
    final pk = await getPublicKey(requestingAtsign);
    AtSigningVerificationInput input = AtSigningVerificationInput(
        jsonEncode(payload), base64Decode(signature), pk)
      ..signingMode = AtSigningMode.data
      ..signingAlgoType = signingAlgo
      ..hashingAlgoType = hashingAlgo;

    AtSigningResult svr = atClient.atChops!.verify(input);
    logger.info('Signing Verification Result: $svr');
    logger.info('svr.result is a ${svr.result.runtimeType}');
    logger.info('svr.result is ${svr.result}');
    if (svr.result != true) {
      throw AtSigningVerificationException(
          'signature verification returned false using cached public key for '
          '$requestingAtsign $pk');
    }
  }

  Future<String> getPublicKey(String atSign) async {
    atSign = atSign.toAtsign();

    String? cached = lookupPubKey(atSign);
    if (cached != null) return cached;

    var s = 'public:publickey$atSign';
    final AtValue av = await atClient.get(AtKey.fromString(s));
    if (av.value == null) {
      throw AtPublicKeyNotFoundException('Failed to retrieve $s');
    }
    if (av.value is! String) {
      throw IllegalStateException('Value of $s is not a String');
    }

    cachePubKey(atSign, av.value);

    return av.value;
  }

  // In memory caching of public keys (to reduce latency)

  @visibleForTesting
  final Map<String, (String, Timer)> pubKeyCache = {};

  @visibleForTesting
  void cachePubKey(String atSign, String pubKey) {
    if (publicKeyCacheSettings == null) return;

    // Create a timer to auto purge the cache
    final timer = Timer(publicKeyCacheSettings!.cacheExpiry, () {
      pubKeyCache.remove(atSign);
    });
    pubKeyCache[atSign] = (pubKey, timer);
  }

  @visibleForTesting
  String? lookupPubKey(String atSign) {
    if (publicKeyCacheSettings == null) return null;
    if (!publicKeyCacheSettings!.resetOnLookup) return pubKeyCache[atSign]?.$1;

    final cacheValue = pubKeyCache[atSign];
    if (cacheValue == null) return null;

    if (publicKeyCacheSettings?.resetOnLookup ?? false) {
      // Cancel the existing timer and create a new one
      cacheValue.$2.cancel();
      final timer = Timer(publicKeyCacheSettings!.cacheExpiry, () {
        pubKeyCache.remove(atSign);
      });
      pubKeyCache[atSign] = (cacheValue.$1, timer);
    }
    return cacheValue.$1;
  }
}
