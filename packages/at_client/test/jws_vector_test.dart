import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart' show ApskSigningKey, apskAdvertisement;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

import 'test_utils/envelope_tamper.dart';

/// The committed JWS vectors (`test/vectors/jws_envelope.json`) against
/// our own verifier — the other half of the off-the-shelf check
/// (`tool/verify_jws_vectors.mjs`, which hands the same bytes to an
/// implementation that is not ours).
///
/// The vectors are FIXED bytes: if our verifier drifts, this goes red even
/// though sign→verify round trips would stay green (a round trip agrees with
/// itself about any drift). And the RS256 arm re-signs and compares the full
/// envelope byte-for-byte — PKCS#1 v1.5 is deterministic — so producer drift
/// is caught too. ML-DSA signing is hedged (randomised), so that arm can
/// only be verified, not re-signed.
void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors =
        jsonDecode(File('test/vectors/jws_envelope.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  test('the RS256 vector verifies, and tampering is refused', () async {
    final arm = vectors['rs256'] as Map<String, dynamic>;
    final envelope = SignedEnvelope.fromJson(arm['envelope'] as Map);

    await verifyEnvelope(envelope,
        signerPublicKey: arm['apskPublicKey'] as String,
        expecting: EnvelopeType.app);
    expect(envelope.payload, vectors['payload']);
    expect(envelope.signerEnrollmentId, 'vector-1');

    await expectLater(
        () => verifyEnvelope(envelope.withPayloadJson({'doc': 'tampered'}),
            signerPublicKey: arm['apskPublicKey'] as String,
            expecting: EnvelopeType.app),
        throwsA(isA<AtSigningVerificationException>()));
  });

  test('the RS256 vector re-signs to the identical envelope', () {
    final arm = vectors['rs256'] as Map<String, dynamic>;

    final resigned = signEnvelope(vectors['payload'],
        keys: [
          ApkamSigningKeys(
              algorithm: SigningAlgoType.rsa2048,
              publicKey: arm['apskPublicKey'] as String,
              privateKey: arm['privateKey'] as String)
        ],
        enrollmentId: 'vector-1',
        type: EnvelopeType.app);

    expect(resigned.toJson(), arm['envelope'],
        reason: 'PKCS#1 v1.5 is deterministic, so any byte of producer '
            'drift — payload encoding, header order, base64url, signing '
            'input — shows up here');
  });

  test('the ML-DSA-65 vector verifies, and tampering is refused', () async {
    final arm = vectors['mlDsa65'] as Map<String, dynamic>;
    final envelope = SignedEnvelope.fromJson(arm['envelope'] as Map);
    final apsk = jsonEncode(apskAdvertisement(keys: [
      ApskSigningKey.forPublicKey(
          alg: SigningAlgoType.mldsa65, pub: arm['publicKey'] as String)
    ]));

    await verifyEnvelope(envelope,
        signerPublicKey: apsk, expecting: EnvelopeType.app);
    expect(envelope.payload, vectors['payload']);

    await expectLater(
        () => verifyEnvelope(envelope.withPayloadJson({'doc': 'tampered'}),
            signerPublicKey: apsk, expecting: EnvelopeType.app),
        throwsA(isA<AtSigningVerificationException>()));
  });
}
