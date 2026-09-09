import 'dart:convert' show base64Encode, jsonEncode;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, SigningAlgoType;
import 'package:at_client/at_client_mixins.dart' show makeActivationPqNative;
import 'package:at_client/src/preference/pq_posture.dart' show PqPosture;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope, verifyEnvelope;
import 'package:at_commons/at_commons.dart' show AtBytes, AtRootDomain;
import 'package:test/test.dart';

/// What `makeActivationPqNative` stamps on an `AtOnboardingRequest`, exercised
/// through the metadata builder it installs.
void main() {
  const atSign = '@alice';

  /// An ML-DSA APKAM keypair in AtKeys' flat fields, base64 of the raw keys.
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

  // NOTE: rsa2048 deliberately — every test below asserts the request comes
  // back carrying mldsa65, and a fixture that started there would be green
  // whether or not `makeActivationPqNative` moved it.
  AtOnboardingRequest request() => AtOnboardingRequest(atSign,
      signingAlgoType: SigningAlgoType.rsa2048,
      rootDomain: AtRootDomain('vip', 64));

  test('at pqActive the activation carries an ML-DSA-65 signing key', () async {
    // NOTE: this must mint the algorithm the enrollment will KEEP. Minting
    // rsa2048 leaves the first start finding ML-DSA missing, minting a second
    // keypair and republishing `_apsk` — orphaning the key this activation
    // advertised and breaking any link conveyed against that exact value.
    final r = request();
    await makeActivationPqNative(r,
        atSign: atSign,
        dataSigningKeyAlgorithms: PqPosture.pqActive.dataSigningKeyAlgorithms);

    expect(r.advertisedSigningKey?.algorithm, SigningAlgoType.mldsa65);
    expect(r.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the authentication key is ML-DSA at both postures; what '
            'pqActive changes is the SIGNING key beside it');
  });

  test('the activation carries an rsa2048 signing key of its own', () async {
    final r = request();
    await makeActivationPqNative(r,
        atSign: atSign,
        dataSigningKeyAlgorithms: PqPosture.pqReady.dataSigningKeyAlgorithms);

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
    // NOTE: `_apsk` names the signing key, and a peer resolves it to verify
    // this key package before sealing anything to the enrollment. Signing the
    // package with the APKAM key instead activates the atSign successfully and
    // leaves it unable to receive a secret from anyone.
    final (io, apkamPublic) = await mlDsaKeys();
    final r = request();
    await makeActivationPqNative(r,
        atSign: atSign,
        dataSigningKeyAlgorithms: PqPosture.pqReady.dataSigningKeyAlgorithms);

    final envelope = SignedEnvelope.fromJson(
        (await r.metadataBuilder!(io))!['keyPackage'] as Map);

    await verifyEnvelope(envelope,
        signerPublicKey: r.advertisedSigningKey!.publicKey,
        expecting: EnvelopeType.keyPackage);

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
    // NOTE: a record naming one key and a package signed by another verifies
    // against neither, and nothing says so until a peer silently declines to
    // seal.
    final (io, _) = await mlDsaKeys();
    final r = request();
    await makeActivationPqNative(r,
        atSign: atSign,
        dataSigningKeyAlgorithms: PqPosture.pqReady.dataSigningKeyAlgorithms);

    final envelope = SignedEnvelope.fromJson(
        (await r.metadataBuilder!(io))!['keyPackage'] as Map);

    await verifyEnvelope(envelope,
        signerPublicKey: r.advertisedSigningKey!.publicKey,
        expecting: EnvelopeType.keyPackage);
  });
}
