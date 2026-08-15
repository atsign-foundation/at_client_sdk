import 'dart:convert' show base64Encode, jsonEncode;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, SigningAlgoType;
import 'package:at_client/at_client_mixins.dart' show makeActivationPqNative;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope, verifyEnvelope;
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

  test('the activation carries an rsa2048 signing key of its own', () async {
    final r = request();
    makeActivationPqNative(r, atSign: atSign);

    expect(r.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the AUTHENTICATION key goes post-quantum: only the atServer '
            'verifies it, and that is the operator\'s own infrastructure');
    expect(r.advertisedSigningKey?.algorithm, SigningAlgoType.rsa2048,
        reason: 'while the SIGNING key stays classical, because every peer '
            'verifies it and the fleet is not the operator\'s to upgrade. A '
            'single active rsa2048 entry is also the one _apsk spelling every '
            'deployed reader parses');
  });

  test('the stamped key package verifies against the SIGNING key', () async {
    // Ruling 98.3 as amended: a peer resolves this enrollment's `_apsk` to
    // verify its key package before sealing anything to it, and `_apsk` names
    // the signing key. Signing the package with the APKAM key instead would
    // activate the atSign successfully and leave it unable to receive a
    // secret from anyone.
    final (io, apkamPublic) = await mlDsaKeys();
    final r = request();
    makeActivationPqNative(r, atSign: atSign);

    final envelope = SignedEnvelope.fromJson(
        (await r.metadataBuilder!(io))!['keyPackage'] as Map);

    await verifyEnvelope(envelope,
        signerPublicKey: r.advertisedSigningKey!.publicKey,
        expecting: EnvelopeType.keyPackage);

    // The differential. Without it this passes for a build that never moved
    // the signer, since a package signed by the APKAM key is still a validly
    // signed package — it just verifies against the wrong record.
    await expectLater(
      () => verifyEnvelope(envelope,
          signerPublicKey: jsonEncode(apskAdvertisement(keys: [
            ApskSigningKey.forPublicKey(
                alg: SigningAlgoType.mldsa65, pub: apkamPublic)
          ])),
          expecting: EnvelopeType.keyPackage),
      throwsA(isA<Exception>()),
      reason: 'the ML-DSA APKAM key must NOT verify it: that key '
          'authenticates connections and signs nothing once the enrollment '
          'owns a signing key, and _apsk does not name it',
    );

    expect(envelope.signerEnrollmentId, isNull,
        reason: 'an onboard has no enrollment id to stamp: this signs before '
            'the atServer has assigned one');
  });

  test('the request and the builder carry the SAME keypair', () async {
    // The failure this function exists to prevent, in its second form: a
    // record naming one key and a package signed by another verifies against
    // neither, and nothing says so until a peer silently declines to seal.
    final (io, _) = await mlDsaKeys();
    final r = request();
    makeActivationPqNative(r, atSign: atSign);

    final envelope = SignedEnvelope.fromJson(
        (await r.metadataBuilder!(io))!['keyPackage'] as Map);

    await verifyEnvelope(envelope,
        signerPublicKey: r.advertisedSigningKey!.publicKey,
        expecting: EnvelopeType.keyPackage);
  });
}
