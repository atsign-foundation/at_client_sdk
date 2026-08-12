import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show apskAdvertisement;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

/// Every form a published `_apsk` comes in, and the verify that reads them.
///
/// Two forms, because which one a record holds depends on what wrote it: the
/// **bare** RSA string, published by every released client, by a connection
/// with no enrollment id, and by the atServer for a plain-legacy enrollment;
/// and the **array**, composed by an enrolling client and written verbatim by
/// the atServer at approval. A reader accepts both.
///
/// Two properties carry the design. The **key's own declaration is
/// authoritative** — a lie in the envelope's `signingAlgo` can never select a
/// weaker routine than the published key calls for. And the **array is
/// unmistakable** — an old bare-RSA parser meeting one fails loudly rather
/// than mis-reading it, which is precisely why a plain-legacy enrollment
/// publishes the bare form instead.
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

    test('a structured value that advertises no keys is refused', () {
      expect(
          () => parseApskValue('{"v":1,"signingAlgo":"mldsa65","pub":"AAEC"}'),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'the array is the only structured form; anything else that '
              'starts with { advertises no key this build can read, and a '
              'guessed algorithm turns a key mismatch into silent acceptance '
              'of whatever the server sent');
    });

    test('an array value names the algorithm of the key it advertises', () {
      final array = jsonEncode(apskAdvertisement(
          apkamPublicKey: 'AAEC', signingAlgo: SigningAlgoType.mldsa65));

      final parsed = parseApskValue(array);
      expect(parsed.signingAlgo, SigningAlgoType.mldsa65);
      expect(parsed.publicKey, 'AAEC',
          reason: 'this is the form an enrollment publishes, so it is the one '
              'an approver meets when verifying a freshly advertised key '
              'package');
    });

    test('an array of nothing understood is refused, not fallen back from', () {
      expect(
          () => parseApskValue('{"v":1,"keys":['
              '{"kid":"k1","use":"sign","alg":"post2030","pub":"AAEC"}]}'),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'no downgrade and no fallback to a derivable legacy key — '
              'the signature means something only if the verifier used the '
              'key the signer published');
    });

    test('an array skips what it cannot use and reads what it can', () {
      final parsed = parseApskValue('{"v":1,"keys":['
          '{"kid":"k1","use":"sign","alg":"post2030","pub":"AAEC"},'
          '{"kid":"k2","use":"sign","alg":"rsa2048","pub":"CCEC"}]}');

      expect(parsed.signingAlgo, SigningAlgoType.rsa2048);
      expect(parsed.publicKey, 'CCEC');
    });

    test('the array form is unmistakable to a bare-RSA consumer', () {
      final array = jsonEncode(apskAdvertisement(
          apkamPublicKey: 'AAEC', signingAlgo: SigningAlgoType.mldsa65));

      // What an old parser does with the value: treat it as base64 RSA key
      // material. It must throw, never quietly produce a key.
      expect(() => base64Decode(array), throwsA(isA<FormatException>()),
          reason: 'NoPorts and its peers parse _apsk as a bare RSA key today; '
              'the array must fail their parse loudly, never mis-read — which '
              'is why a plain-legacy enrollment publishes the bare form and '
              'not this');
    });
  });

  group('verifyEnvelope, every published form', () {
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

    /// What a 4.x enrollment's signer produces: the same envelope shape,
    /// signed ML-DSA-65, naming that algorithm in its protected header.
    Map<String, Object?> mlDsaEnvelope() => signEnvelope(payload,
        keys: ApkamSigningKeys(
            publicKey: base64Encode(mlDsaPair.publicKey),
            privateKey: base64Encode(mlDsaPair.secretKey)),
        enrollmentId: 'enroll-pq',
        signingAlgo: SigningAlgoType.mldsa65);

    /// [envelope] with its protected header replaced, so a test can make the
    /// envelope claim an algorithm its key does not match. The header is
    /// inside the signature, so this is a re-stamp rather than an edit — and
    /// it is the only way to build the mismatch at all.
    Map<String, Object?> claimingAlg(
            Map<String, Object?> envelope, String alg) =>
        {
          ...envelope,
          'signatures': [
            {
              ...((envelope['signatures'] as List).single as Map)
                  .cast<String, Object?>(),
              'protected': base64Url
                  .encode(utf8.encode(jsonEncode({'alg': alg, 'v': 1})))
                  .replaceAll('=', ''),
            }
          ],
        };

    /// The `_apsk` an ML-DSA enrollment publishes: what its client composed,
    /// written verbatim by the atServer at approval.
    String mlDsaApsk() => jsonEncode(apskAdvertisement(
        apkamPublicKey: base64Encode(mlDsaPair.publicKey),
        signingAlgo: SigningAlgoType.mldsa65));

    test('a bare RSA _apsk verifies an RSA envelope — today\'s traffic',
        () async {
      await verifyEnvelope(rsaEnvelope(),
          signerPublicKey: rsaPair.atPublicKey.publicKey);
    });

    test('an array ML-DSA _apsk verifies an ML-DSA envelope', () async {
      // The whole approval path in one assertion: this is the value the
      // atServer publishes from what the enrolling client composed, and the
      // approver verifies the advertised key package against exactly it.
      await verifyEnvelope(mlDsaEnvelope(), signerPublicKey: mlDsaApsk());
    });

    test('an array RSA _apsk refuses an envelope claiming ML-DSA-65', () async {
      final apsk = jsonEncode(apskAdvertisement(
          apkamPublicKey: rsaPair.atPublicKey.publicKey,
          signingAlgo: SigningAlgoType.rsa2048));
      final envelope = claimingAlg(rsaEnvelope(), 'ML-DSA-65');

      await expectLater(() => verifyEnvelope(envelope, signerPublicKey: apsk),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'the array carries the algorithm explicitly, so the claim '
              'cannot select a routine the published key does not call for');
    });

    test('signEnvelope signs ML-DSA when asked, and the result verifies',
        () async {
      final envelope = signEnvelope(payload,
          keys: ApkamSigningKeys(
              publicKey: base64Encode(mlDsaPair.publicKey),
              privateKey: base64Encode(mlDsaPair.secretKey)),
          enrollmentId: 'enroll-pq',
          signingAlgo: SigningAlgoType.mldsa65);
      final entry = (envelope['signatures'] as List).single as Map;
      expect(
          jsonDecode(utf8.decode(base64Decode(
              base64.normalize(entry['protected'] as String))))['alg'],
          'ML-DSA-65');
      expect(
          base64Decode(base64.normalize(entry['signature'] as String)).length,
          3309,
          reason: 'an ML-DSA-65 signature is 3309 bytes — an RSA-sized '
              'signature here means the sign dispatch ignored signingAlgo');

      final apsk = mlDsaApsk();
      await verifyEnvelope(envelope, signerPublicKey: apsk);

      envelope['payload'] = base64Url
          .encode(utf8.encode('"a different text"'))
          .replaceAll('=', '');
      await expectLater(() => verifyEnvelope(envelope, signerPublicKey: apsk),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('signEnvelope refuses an algorithm it has no signing code for', () {
      expect(
          () => signEnvelope(payload,
              keys: ApkamSigningKeys(publicKey: 'x', privateKey: 'y'),
              signingAlgo: SigningAlgoType.ecc_secp256r1),
          throwsA(isA<ArgumentError>()));
    });

    test('a tampered ML-DSA envelope fails', () async {
      final apsk = mlDsaApsk();
      final envelope = mlDsaEnvelope();
      envelope['payload'] = base64Url
          .encode(utf8.encode('"a different text"'))
          .replaceAll('=', '');

      await expectLater(() => verifyEnvelope(envelope, signerPublicKey: apsk),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'control: the ML-DSA branch must actually verify, or the '
              'happy path above proves routing and nothing else');
    });

    test(
        'an envelope claiming rsa2048 against an ML-DSA _apsk is '
        'refused', () async {
      final apsk = mlDsaApsk();

      await expectLater(
          () => verifyEnvelope(rsaEnvelope(), signerPublicKey: apsk),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'the key\'s declaration is authoritative — the claim cannot '
              'select a weaker routine than the published key calls for');
    });

    test('an envelope claiming ML-DSA-65 against a bare RSA key is refused',
        () async {
      final envelope = claimingAlg(rsaEnvelope(), 'ML-DSA-65');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'a bare key is RSA by definition; an envelope claiming '
              'otherwise is lying about something, and the lie fails');
    });
  });
}
