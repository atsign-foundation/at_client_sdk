import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart' show ApskSigningKey, apskAdvertisement;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart'
    show EnvelopeVerified, PublishedApsk, verifySignedEnvelope;
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

import 'test_utils/envelope_tamper.dart';

/// The committed JWS vectors (`test/vectors/jws_envelope.json`) against our
/// own verifier.
///
/// The vectors are fixed bytes, so verifier drift reddens this where a
/// sign→verify round trip would stay green; ML-DSA signing is hedged, so those
/// arms can only be verified, never re-signed. The `rs256` and `mlDsa65` arms
/// are envelopes as at_client 4.0.0 signed them, naming no Atsign; the
/// `rs256Iss` and `mlDsa65Iss` arms are what this build signs.
void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors =
        jsonDecode(File('test/vectors/jws_envelope.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  String mlDsaApsk(Map<String, dynamic> arm) =>
      jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65, pub: arm['publicKey'] as String)
      ]));

  for (final (name, apskOf) in [
    ('rs256', (Map<String, dynamic> arm) => arm['apskPublicKey'] as String),
    ('rs256Iss', (Map<String, dynamic> arm) => arm['apskPublicKey'] as String),
    ('mlDsa65', mlDsaApsk),
    ('mlDsa65Iss', mlDsaApsk),
  ]) {
    test('the $name vector verifies, and tampering is refused', () async {
      final arm = vectors[name] as Map<String, dynamic>;
      final envelope = SignedEnvelope.fromJson(arm['envelope'] as Map);
      final apsk = apskOf(arm);

      await verifyEnvelope(envelope,
          signerAtSign: '@alice',
          signerPublicKey: apsk,
          expecting: EnvelopeType.app);
      expect(envelope.payload, vectors['payload']);
      expect(envelope.signerEnrollmentId, 'vector-1');

      await expectLater(
          () => verifyEnvelope(envelope.withPayloadJson({'doc': 'tampered'}),
              signerAtSign: '@alice',
              signerPublicKey: apsk,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()));
    });
  }

  test('the at_client 4.0.0 arms name no Atsign, and the others name @alice',
      () {
    for (final name in ['rs256', 'mlDsa65']) {
      expect(
          SignedEnvelope.fromJson(vectors[name]['envelope'] as Map)
              .signature
              .header
              .containsKey('iss'),
          isFalse,
          reason: '$name is frozen as at_client 4.0.0 signed it');
    }
    for (final name in ['rs256Iss', 'mlDsa65Iss']) {
      expect(
          SignedEnvelope.fromJson(vectors[name]['envelope'] as Map)
              .signature
              .iss,
          '@alice');
    }
  });

  for (final (name, apskOf, confirmed) in [
    (
      'rs256',
      (Map<String, dynamic> arm) => arm['apskPublicKey'] as String,
      false
    ),
    (
      'rs256Iss',
      (Map<String, dynamic> arm) => arm['apskPublicKey'] as String,
      true
    ),
    ('mlDsa65', mlDsaApsk, false),
    ('mlDsa65Iss', mlDsaApsk, true),
  ]) {
    test('the $name vector verifies offline, issuerConfirmed $confirmed',
        () async {
      final arm = vectors[name] as Map<String, dynamic>;

      final result = await verifySignedEnvelope(
          SignedEnvelope.fromJson(arm['envelope'] as Map),
          signer: PublishedApsk(
              atSign: '@alice', enrollmentId: 'vector-1', value: apskOf(arm)));

      expect(
          result,
          isA<EnvelopeVerified>()
              .having((r) => r.issuerConfirmed, 'issuerConfirmed', confirmed));
    });
  }

  test('the rs256Iss vector re-signs to the identical envelope', () {
    final arm = vectors['rs256Iss'] as Map<String, dynamic>;

    final resigned = signEnvelope(vectors['payload'],
        atSign: '@alice',
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
}
