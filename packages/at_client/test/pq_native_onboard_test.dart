import 'dart:convert' show base64Encode, jsonEncode;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client_mixins.dart' show makeActivationPqNative;
import 'package:at_client/src/signing/envelope_signature.dart'
    show envelopeVersionOf, verifyEnvelope;
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

  test('the stamp defaults the key package envelope to version 1', () async {
    final (io, _) = await mlDsaKeys();
    final r = request();
    makeActivationPqNative(r, atSign: atSign);

    final built = await r.metadataBuilder!(io);
    expect(envelopeVersionOf(built!['keyPackage'] as Map), 1,
        reason: 'the wrapper frozen in the write-once metadata.keyPackage '
            'must not move without being asked');
  });

  test('a threaded envelopeVersion reaches the frozen key package', () async {
    final (io, public) = await mlDsaKeys();
    final r = request();
    makeActivationPqNative(r, atSign: atSign, envelopeVersion: 2);

    final envelope = (await r.metadataBuilder!(io))!['keyPackage'] as Map;
    expect(envelopeVersionOf(envelope), 2,
        reason: 'pqNativeOnboard passes preference.posture.envelopeVersion '
            'through this parameter — dropping the plumbing leaves every '
            'postured onboard emitting v1');
    // And the v2 shape still verifies against the same ML-DSA APKAM key —
    // in the tagged, self-describing form the atServer serves an ML-DSA
    // _apsk in (a bare value is classified as an RSA key by the verifier).
    await verifyEnvelope(envelope,
        signerPublicKey:
            jsonEncode({'signingAlgo': 'mldsa65', 'publicKey': public}));
  });
}
