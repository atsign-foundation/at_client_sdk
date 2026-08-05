import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

/// The `_apsk` two-stage ladder (`decisions.md` 39): the final 3.x publishes
/// the bare RSA form exactly as today while its verify learns the tagged,
/// self-describing form 4.x's new enrollments will publish.
///
/// Two properties carry the design. The **key's own declaration is
/// authoritative** — a lie in the envelope's `signingAlgo` can never select a
/// weaker routine than the published key calls for. And the **tagged form is
/// unmistakable** — an old bare-RSA parser meeting it fails loudly, and this
/// build meeting an algorithm it has no code for refuses rather than guesses.
void main() {
  const payload = 'the signable text';

  group('parseApskValue', () {
    test('a bare value is an RSA key, verbatim', () {
      final parsed = parseApskValue('MIIBIjANBgkq-not-really-but-bare');

      expect(parsed.signingAlgo, SigningAlgoType.rsa2048);
      expect(parsed.publicKey, 'MIIBIjANBgkq-not-really-but-bare',
          reason: 'the bare form is what every published _apsk carries today, '
              'and what NoPorts parses — it must round-trip untouched');
    });

    test('a tagged value names its own algorithm', () {
      final tagged = encodeTaggedApsk(
          signingAlgo: SigningAlgoType.mldsa65, publicKey: 'AAEC');

      final parsed = parseApskValue(tagged);
      expect(parsed.signingAlgo, SigningAlgoType.mldsa65);
      expect(parsed.publicKey, 'AAEC');
    });

    test('an unknown algorithm is refused, not guessed', () {
      expect(
          () => parseApskValue(
              '{"v":1,"signingAlgo":"post2030","publicKey":"AAEC"}'),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'a guessed algorithm turns a key mismatch into silent '
              'acceptance of whatever the server sent');
    });

    test('the tagged form is unmistakable to a bare-RSA consumer', () {
      final tagged = encodeTaggedApsk(
          signingAlgo: SigningAlgoType.mldsa65, publicKey: 'AAEC');

      // What an old parser does with the value: treat it as base64 RSA key
      // material. It must throw, never quietly produce a key.
      expect(() => base64Decode(tagged), throwsA(isA<FormatException>()),
          reason: 'NoPorts and its peers parse _apsk as a bare RSA key today; '
              'the new form must fail their parse loudly, never mis-read');
    });
  });

  group('verifyEnvelope, two formats', () {
    late AtPkamKeyPair rsaPair;
    late ({Uint8List publicKey, Uint8List secretKey}) mlDsaPair;

    setUpAll(() async {
      rsaPair = AtChopsUtil.generateAtPkamKeyPair();
      mlDsaPair = await MlDsa65PureDartAlgo().generateKeyPair();
    });

    Map<String, Object?> rsaEnvelope() => signEnvelope(payload,
        keys: ApkamSigningKeys(
            publicKey: rsaPair.atPublicKey.publicKey,
            privateKey: rsaPair.atPrivateKey.privateKey));

    /// What a 4.x enrollment's signer will produce: the same envelope shape,
    /// signed ML-DSA-65, claiming its algorithm.
    Future<Map<String, Object?>> mlDsaEnvelope() async {
      final signature = await MlDsa65PureDartAlgo().signBytes(
          utf8.encode(signableTextOf(payload)),
          secretKey: mlDsaPair.secretKey);
      return {
        'payload': payload,
        'signature': base64Encode(signature),
        'hashingAlgo': HashingAlgoType.sha256.name,
        'signingAlgo': SigningAlgoType.mldsa65.name,
        'enrollmentId': 'enroll-pq',
      };
    }

    test('a bare RSA _apsk verifies an RSA envelope — today\'s traffic',
        () async {
      await verifyEnvelope(rsaEnvelope(),
          signerPublicKey: rsaPair.atPublicKey.publicKey);
    });

    test('a tagged ML-DSA _apsk verifies an ML-DSA envelope', () async {
      final apsk = encodeTaggedApsk(
          signingAlgo: SigningAlgoType.mldsa65,
          publicKey: base64Encode(mlDsaPair.publicKey));

      await verifyEnvelope(await mlDsaEnvelope(), signerPublicKey: apsk);
    });

    test('a tampered ML-DSA envelope fails', () async {
      final apsk = encodeTaggedApsk(
          signingAlgo: SigningAlgoType.mldsa65,
          publicKey: base64Encode(mlDsaPair.publicKey));
      final envelope = await mlDsaEnvelope();
      envelope['payload'] = 'a different text';

      await expectLater(() => verifyEnvelope(envelope, signerPublicKey: apsk),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'control: the ML-DSA branch must actually verify, or the '
              'happy path above proves routing and nothing else');
    });

    test(
        'an envelope claiming rsa2048 against a tagged ML-DSA key is '
        'refused', () async {
      final apsk = encodeTaggedApsk(
          signingAlgo: SigningAlgoType.mldsa65,
          publicKey: base64Encode(mlDsaPair.publicKey));

      await expectLater(
          () => verifyEnvelope(rsaEnvelope(), signerPublicKey: apsk),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'the key\'s declaration is authoritative — the claim cannot '
              'select a weaker routine than the published key calls for');
    });

    test('an envelope claiming mldsa65 against a bare RSA key is refused',
        () async {
      final envelope = rsaEnvelope();
      envelope['signingAlgo'] = SigningAlgoType.mldsa65.name;

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'a bare key is RSA by definition; an envelope claiming '
              'otherwise is lying about something, and the lie fails');
    });
  });
}
