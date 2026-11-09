// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart' show ApskSigningKey, apskAdvertisement;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:test/test.dart';

/// at_client 4.0.0's verifier against the JWS vectors this tree commits.
///
/// Catalogue: features/at_client/envelope_signer_atsign.feature
void main() {
  final vectors = jsonDecode(
      File('../../../packages/at_client/test/vectors/jws_envelope.json')
          .readAsStringSync()) as Map<String, dynamic>;

  String mlDsaApsk(Map<String, dynamic> arm) =>
      jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65, pub: arm['publicKey'] as String)
      ]));

  for (final (name, apskOf) in [
    ('rs256Iss', (Map<String, dynamic> arm) => arm['apskPublicKey'] as String),
    ('mlDsa65Iss', mlDsaApsk),
    ('rs256', (Map<String, dynamic> arm) => arm['apskPublicKey'] as String),
    ('mlDsa65', mlDsaApsk),
  ]) {
    test(
        'An envelope that names its Atsign verifies on at_client 4.0.0: the '
        '$name vector', () async {
      final arm = vectors[name] as Map<String, dynamic>;
      final envelope = SignedEnvelope.fromJson(arm['envelope'] as Map);
      final header = jsonDecode(utf8.decode(base64Url
          .decode(base64Url.normalize(envelope.signature.protected)))) as Map;
      expect(header.containsKey('iss'), name.endsWith('Iss'),
          reason: 'the premise: the Iss arms carry the claim');

      await verifyEnvelope(envelope,
          signerPublicKey: apskOf(arm), expecting: EnvelopeType.app);

      final tampered = SignedEnvelope.fromJson({
        ...envelope.toJson(),
        'payload': base64Url
            .encode(utf8.encode(jsonEncode({'doc': 'tampered'})))
            .replaceAll('=', ''),
      });
      await expectLater(
          verifyEnvelope(tampered,
              signerPublicKey: apskOf(arm), expecting: EnvelopeType.app),
          throwsA(isA<Exception>()
              .having((x) => '$x', 'message', contains('does not verify'))),
          reason: 'the control: this verifier refuses what does not verify');
    });
  }
}
