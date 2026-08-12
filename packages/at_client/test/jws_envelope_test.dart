import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show apskAdvertisement;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

/// The signed-envelope shape: RFC 7515 **General** JSON Serialization,
/// `{payload, signatures: [{protected, signature}]}`, with `{alg, kid, v}`
/// inside each protected header.
///
/// The arms that matter most here are the ones a lazy suite collapses:
///
/// - **The RSA arm specifically.** An unpadded RSA-2048 signature is 342
///   base64url chars — a length Dart's `base64Decode` throws on — while
///   ML-DSA-65's 4412 decodes fine. A suite that only exercises ML-DSA goes
///   green on code that cannot decode a single RSA signature.
/// - **The claims are signed.** `alg` and `kid` live inside the protected
///   header, so a relabel breaks the signature. That is asserted by tampering,
///   not claimed.
/// - **The array is an array.** One entry today, but an envelope carrying no
///   `signatures` — or an empty one — must be refused rather than verifying
///   vacuously.
void main() {
  late AtPkamKeyPair rsaPair;
  late ({Uint8List publicKey, Uint8List secretKey}) mlDsaPair;
  const payload = {'hello': 'world', 'n': 1};

  setUpAll(() async {
    rsaPair = AtChopsUtil.generateAtPkamKeyPair();
    mlDsaPair = await MlDsa65PureDartAlgo().generateKeyPair();
  });

  ApkamSigningKeys rsaKeys() => ApkamSigningKeys(
      publicKey: rsaPair.atPublicKey.publicKey,
      privateKey: rsaPair.atPrivateKey.privateKey);

  ApkamSigningKeys mlDsaKeys() => ApkamSigningKeys(
      publicKey: base64Encode(mlDsaPair.publicKey),
      privateKey: base64Encode(mlDsaPair.secretKey));

  String mlDsaApsk() => jsonEncode(apskAdvertisement(
      apkamPublicKey: base64Encode(mlDsaPair.publicKey),
      signingAlgo: SigningAlgoType.mldsa65));

  Map<String, Object?> rsaEnvelope({String? enrollmentId = 'enroll-1'}) =>
      signEnvelope(payload, keys: rsaKeys(), enrollmentId: enrollmentId);

  Map<String, Object?> mlDsaEnvelope() => signEnvelope(payload,
      keys: mlDsaKeys(),
      enrollmentId: 'enroll-pq',
      signingAlgo: SigningAlgoType.mldsa65);

  String b64u(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');

  String decodeB64u(String s) => utf8.decode(base64Decode(base64.normalize(s)));

  /// The sole signature entry, which every envelope written today carries.
  Map<String, Object?> entryOf(Map<String, Object?> envelope) =>
      ((envelope['signatures'] as List).single as Map).cast<String, Object?>();

  /// Replaces the sole signature entry's [member], leaving the rest intact —
  /// the tamper lever for everything inside `signatures`.
  void tamper(Map<String, Object?> envelope, String member, String value) {
    envelope['signatures'] = [entryOf(envelope)..[member] = value];
  }

  group('the envelope shape, RSA arm', () {
    test('signs, verifies, and survives the base64 padding trap', () async {
      final envelope = rsaEnvelope();

      expect(envelope.keys.toList(), ['payload', 'signatures']);
      final entry = entryOf(envelope);
      expect(entry.keys.toList(), ['protected', 'signature']);
      for (final text in [
        envelope['payload'] as String,
        entry['protected'] as String,
        entry['signature'] as String,
      ]) {
        expect(text.contains('='), isFalse,
            reason: 'RFC 7515 base64url is unpadded');
      }
      // The measured trap: 256 signature bytes → 342 unpadded chars, a length
      // the naive decode throws on. Assert the length so this test can never
      // silently stop covering the throwing case.
      final signature = entry['signature'] as String;
      expect(signature.length, 342);
      expect(() => base64Decode(signature), throwsA(isA<FormatException>()),
          reason: 'if this stops throwing, the padding trap this arm exists '
              'to cover has moved');

      await verifyEnvelope(envelope,
          signerPublicKey: rsaPair.atPublicKey.publicKey);
    });

    test('the protected header is exactly the pinned bytes', () {
      final headerJson = decodeB64u(entryOf(rsaEnvelope())['protected'] as String);

      // Raw literal, not built from constants: the signature covers these
      // bytes, so the member ORDER is cryptographically bound.
      expect(headerJson, '{"alg":"RS256","kid":"enroll-1","v":1}');
    });

    test('a tampered payload fails', () async {
      final envelope = rsaEnvelope();
      envelope['payload'] = b64u('{"hello":"universe","n":1}');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a tampered protected header fails: the claims are signed', () async {
      final envelope = rsaEnvelope();
      // Same alg, same v, different kid. The claim is inside the signature,
      // so a relabel cannot go unnoticed.
      tamper(envelope, 'protected',
          b64u('{"alg":"RS256","kid":"enroll-2","v":1}'));

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test("alg cannot overrule the published key's declaration", () async {
      final envelope = rsaEnvelope();
      tamper(envelope, 'protected',
          b64u('{"alg":"ML-DSA-65","kid":"enroll-1","v":1}'));

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message, 'message', contains('refusing the mismatch'))));
    });

    test('a corrupted signature fails', () async {
      final envelope = rsaEnvelope();
      final signature = entryOf(envelope)['signature'] as String;
      tamper(envelope, 'signature',
          signature.replaceRange(0, 1, signature[0] == 'A' ? 'B' : 'A'));

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('the envelope shape, ML-DSA arm', () {
    test('signs and verifies under the array _apsk', () async {
      final envelope = mlDsaEnvelope();

      final signature = entryOf(envelope)['signature'] as String;
      expect(signature.length, 4412,
          reason: 'ML-DSA-65 is 3309 signature bytes — and 4412 % 4 == 0, so '
              'this arm alone can NEVER catch a missing base64 '
              'normalisation; that is what the RSA arm is for');
      expect(signature.contains('='), isFalse);

      final headerJson =
          decodeB64u(entryOf(envelope)['protected'] as String);
      expect(headerJson, '{"alg":"ML-DSA-65","kid":"enroll-pq","v":1}');

      await verifyEnvelope(envelope, signerPublicKey: mlDsaApsk());
    });

    test('a tampered payload fails', () async {
      final envelope = mlDsaEnvelope();
      envelope['payload'] = b64u('{"hello":"universe","n":1}');

      await expectLater(
          () => verifyEnvelope(envelope, signerPublicKey: mlDsaApsk()),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('reading an envelope', () {
    test('envelopePayloadOf decodes what a direct read cannot', () {
      final envelope = rsaEnvelope();

      expect(envelope['payload'], isA<String>(),
          reason: 'the raw member is base64url text, never the payload');
      expect(envelopePayloadOf(envelope), payload);
    });

    test('envelopeSignerOf reads the kid claim', () {
      expect(envelopeSignerOf(rsaEnvelope()), 'enroll-1');
    });

    test('no enrollment, no claim — and no kid member at all', () {
      final envelope = rsaEnvelope(enrollmentId: null);

      expect(envelopeSignerOf(envelope), isNull);
      expect(decodeB64u(entryOf(envelope)['protected'] as String),
          '{"alg":"RS256","v":1}',
          reason: 'a guessed or sentinel id would be frozen inside the '
              'signature where nobody could correct it');
    });

    test('a String payload becomes JSON, so decoding is unconditional', () {
      final envelope = signEnvelope('just text', keys: rsaKeys());

      expect(envelopePayloadOf(envelope), 'just text',
          reason: 'what comes out of base64url is JSON, whatever went in');
    });
  });

  group('refusals', () {
    test('an envelope with no signatures array is refused, not a cast error',
        () async {
      final envelope = rsaEnvelope();
      envelope.remove('signatures');

      expect(() => envelopeSignerOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('an empty signatures array is refused, not treated as unsigned',
        () async {
      // The arm that matters: an envelope nobody signed must not verify
      // vacuously by having nothing to check.
      final envelope = rsaEnvelope();
      envelope['signatures'] = [];

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('non-empty signatures array'))));
    });

    test('a signatures entry that is not an object is refused', () async {
      final envelope = rsaEnvelope();
      envelope['signatures'] = ['not-an-object'];

      expect(() => envelopeSignerOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('an entry missing its protected header is refused', () async {
      final envelope = rsaEnvelope();
      envelope['signatures'] = [
        {'signature': entryOf(envelope)['signature']}
      ];

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
      expect(() => envelopeSignerOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a payload that does not decode is refused', () {
      final envelope = rsaEnvelope();
      envelope['payload'] = 'not!!!base64url';
      expect(() => envelopePayloadOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));

      envelope['payload'] = b64u('{truncated');
      expect(() => envelopePayloadOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a protected header naming another version is refused', () async {
      // The version is inside the signature, so this is not a tamper defence
      // — it is what stops a future shape being read as this one by a build
      // that has no code for it.
      final envelope = rsaEnvelope();
      tamper(envelope, 'protected',
          b64u('{"alg":"RS256","kid":"enroll-1","v":2}'));

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('claims envelope version'))));
    });

    test('a protected header that is not JSON is refused', () {
      final envelope = rsaEnvelope();
      tamper(envelope, 'protected', b64u('{truncated'));

      expect(() => envelopeSignerOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('the producer refuses a signing algorithm it has no mapping for', () {
      expect(
          () => signEnvelope(payload,
              keys: rsaKeys(), signingAlgo: SigningAlgoType.ed25519),
          throwsA(isA<ArgumentError>()),
          reason: 'no envelope signs under Ed25519, and a shape that guessed '
              'an alg name for it would freeze the guess inside a signature');
    });
  });
}
