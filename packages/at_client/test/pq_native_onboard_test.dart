import 'dart:convert' show base64Encode, jsonEncode;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, SigningAlgoType;
import 'package:at_client/at_client_mixins.dart' show makeActivationPqNative;
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope, verifyEnvelope;
import 'package:at_commons/at_commons.dart' show AtBytes, AtRootDomain;
import 'package:test/test.dart';

/// The PQ-native activation stamp, at the unit level: what
/// `makeActivationPqNative` puts on an `AtOnboardingRequest`, exercised by
/// invoking the metadata builder it installs. The live CRAM onboard is
/// `tests/at_functional_test/test/pq_native_onboard_live_test.dart`; this
/// file pins the request-side plumbing that run cannot vary per arm.
void main() {
  const atSign = '@alice';

  /// The AtKeys the builder will be handed at onboard time: an ML-DSA APKAM
  /// keypair in the flat fields, base64 of the raw keys — the shape the
  /// PQ-native activation mints.
  Future<(InMemoryAtKeysIo, String)> mlDsaKeys() async {
    final pair = await MlDsa65PureDartAlgo().generateKeyPair();
    final public = base64Encode(pair.publicKey);
    final keys = AtKeys()
      ..apkamPublicKey = AtBytes.fromString(public)
      ..apkamPrivateKey = AtBytes.fromString(base64Encode(pair.secretKey));
    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    return (io, public);
  }

  AtOnboardingRequest request() =>
      AtOnboardingRequest(atSign, rootDomain: AtRootDomain('vip', 64));

  test('the stamped key package verifies against the ML-DSA APKAM key',
      () async {
    final (io, public) = await mlDsaKeys();
    final r = request();
    makeActivationPqNative(r, atSign: atSign);

    final envelope = SignedEnvelope.fromJson(
        (await r.metadataBuilder!(io))!['keyPackage'] as Map);

    // Verified in the array form this enrollment composed and the atServer
    // publishes verbatim — a bare value is classified as an RSA key by the
    // verifier, so the array is what proves the ML-DSA path end to end.
    await verifyEnvelope(envelope,
        signerPublicKey: jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65, pub: public)
      ])));

    expect(envelope.signerEnrollmentId, isNull,
        reason: 'an onboard has no enrollment id to stamp: this signs before '
            'the atServer has assigned one');
  });
}
