import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

/// The JWS wrapper shape (`decisions.md` 48.8, 56.5): RFC 7515 Flattened
/// JSON, readers always-on, producer behind `signEnvelope`'s `version`
/// parameter defaulting to 1.
///
/// The arms that matter most here are the ones a lazy suite collapses:
///
/// - **The RSA arm specifically.** An unpadded RSA-2048 signature is 342
///   base64url chars — a length Dart's `base64Decode` throws on — while
///   ML-DSA-65's 4412 decodes fine. A suite that only exercises ML-DSA goes
///   green on code that cannot decode a single RSA signature.
/// - **The header is signed.** Version 1's `signingAlgo`/`enrollmentId` sit
///   outside the signature; the whole point of the JWS shape is that `alg`
///   and `kid` sit inside it. That is asserted by tampering, not claimed.
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

  String mlDsaApsk() => encodeTaggedApsk(
      signingAlgo: SigningAlgoType.mldsa65,
      publicKey: base64Encode(mlDsaPair.publicKey));

  Map<String, Object?> rsaJws({String? enrollmentId = 'enroll-1'}) =>
      signEnvelope(payload,
          keys: rsaKeys(),
          enrollmentId: enrollmentId,
          version: jwsEnvelopeVersion);

  Map<String, Object?> mlDsaJws() => signEnvelope(payload,
      keys: mlDsaKeys(),
      enrollmentId: 'enroll-pq',
      signingAlgo: SigningAlgoType.mldsa65,
      version: jwsEnvelopeVersion);

  String b64u(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');

  String decodeB64u(String s) => utf8.decode(base64Decode(base64.normalize(s)));

  group('the JWS shape, RSA arm', () {
    test('signs, verifies, and survives the base64 padding trap', () async {
      final envelope = rsaJws();

      expect(envelope.keys.toList(),
          ['v', 'payload', 'protected', 'signature']);
      expect(envelope['v'], 2);
      for (final member in ['payload', 'protected', 'signature']) {
        expect((envelope[member] as String).contains('='), isFalse,
            reason: 'RFC 7515 base64url is unpadded');
      }
      // The measured trap: 256 signature bytes → 342 unpadded chars, a length
      // the naive decode throws on. Assert the length so this test can never
      // silently stop covering the throwing case.
      final signature = envelope['signature'] as String;
      expect(signature.length, 342);
      expect(() => base64Decode(signature), throwsA(isA<FormatException>()),
          reason: 'if this stops throwing, the padding trap this arm exists '
              'to cover has moved');

      await verifyEnvelope(envelope,
          signerPublicKey: rsaPair.atPublicKey.publicKey);
    });

    test('the protected header is exactly the pinned bytes', () {
      final envelope = rsaJws();
      final headerJson = decodeB64u(envelope['protected'] as String);

      // Raw literal, not built from constants: the signature covers these
      // bytes, so the member ORDER is cryptographically bound.
      expect(headerJson, '{"alg":"RS256","kid":"enroll-1","v":2}');
    });

    test('a tampered payload fails', () async {
      final envelope = rsaJws();
      envelope['payload'] = b64u('{"hello":"universe","n":1}');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a tampered protected header fails: the claims are signed',
        () async {
      final envelope = rsaJws();
      // Same alg, same v, different kid: in version 1 this claim sits outside
      // the signature and a relabel goes unnoticed; here it must not.
      envelope['protected'] = b64u('{"alg":"RS256","kid":"enroll-2","v":2}');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test("alg cannot overrule the published key's declaration", () async {
      final envelope = rsaJws();
      envelope['protected'] =
          b64u('{"alg":"ML-DSA-65","kid":"enroll-1","v":2}');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message, 'message', contains('refusing the mismatch'))));
    });

    test('a corrupted signature fails', () async {
      final envelope = rsaJws();
      final signature = envelope['signature'] as String;
      envelope['signature'] =
          signature.replaceRange(0, 1, signature[0] == 'A' ? 'B' : 'A');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('the JWS shape, ML-DSA arm', () {
    test('signs and verifies under the tagged _apsk', () async {
      final envelope = mlDsaJws();

      final signature = envelope['signature'] as String;
      expect(signature.length, 4412,
          reason: 'ML-DSA-65 is 3309 signature bytes — and 4412 % 4 == 0, so '
              'this arm alone can NEVER catch a missing base64 '
              'normalisation; that is what the RSA arm is for');
      expect(signature.contains('='), isFalse);

      final headerJson = decodeB64u(envelope['protected'] as String);
      expect(headerJson, '{"alg":"ML-DSA-65","kid":"enroll-pq","v":2}');

      await verifyEnvelope(envelope, signerPublicKey: mlDsaApsk());
    });

    test('a tampered payload fails', () async {
      final envelope = mlDsaJws();
      envelope['payload'] = b64u('{"hello":"universe","n":1}');

      await expectLater(
          () => verifyEnvelope(envelope, signerPublicKey: mlDsaApsk()),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('the two shapes side by side', () {
    test('the same payload verifies under both, and the arms differ', () async {
      final v1 = signEnvelope(payload, keys: rsaKeys(), enrollmentId: 'e1');
      final v2 = rsaJws(enrollmentId: 'e1');

      await verifyEnvelope(v1, signerPublicKey: rsaPair.atPublicKey.publicKey);
      await verifyEnvelope(v2, signerPublicKey: rsaPair.atPublicKey.publicKey);

      // The differential half: if these ever agree, the test is comparing a
      // case with itself.
      expect(v1['v'], 1);
      expect(v2['v'], 2);
      expect(v1['payload'], isA<Map>());
      expect(v2['payload'], isA<String>());
      expect(v1.containsKey('protected'), isFalse);
      expect(v2.containsKey('signingAlgo'), isFalse);
    });

    test('envelopePayloadOf reads both shapes', () {
      final v1 = signEnvelope(payload, keys: rsaKeys());
      final v2 = rsaJws();

      expect(envelopePayloadOf(v1), same(v1['payload']),
          reason: 'version 1 embeds the payload; no decode to do');
      expect(envelopePayloadOf(v2), payload,
          reason: 'the JWS payload round-trips through base64url JSON');
    });

    test('envelopeSignerOf reads the claim from either home', () {
      expect(
          envelopeSignerOf(signEnvelope(payload,
              keys: rsaKeys(), enrollmentId: 'enroll-1')),
          'enroll-1');
      expect(envelopeSignerOf(rsaJws()), 'enroll-1');
    });

    test('no enrollment, no claim — in either shape', () {
      final v1 = signEnvelope(payload, keys: rsaKeys());
      final v2 = rsaJws(enrollmentId: null);

      expect(envelopeSignerOf(v1), isNull);
      expect(envelopeSignerOf(v2), isNull);
      final headerJson = decodeB64u(v2['protected'] as String);
      expect(headerJson, '{"alg":"RS256","v":2}',
          reason: 'no kid member at all — a guessed or sentinel id would be '
              'frozen inside the signature where nobody could correct it');
    });

    test('a String payload becomes JSON in the JWS shape', () {
      final v2 = signEnvelope('just text',
          keys: rsaKeys(), version: jwsEnvelopeVersion);

      expect(envelopePayloadOf(v2), 'just text',
          reason: 'version 1 signs a String verbatim; the JWS shape encodes '
              'it as JSON so decode is unconditional — either way it '
              'round-trips');
    });
  });

  group('refusals', () {
    test('an unknown wrapper version is refused everywhere, not guessed at',
        () async {
      final envelope = signEnvelope(payload, keys: rsaKeys());
      envelope['v'] = 3;

      expect(() => envelopeVersionOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
      expect(() => envelopePayloadOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
      expect(() => envelopeSignerOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('an absent v is version 1 — the pre-2026-08-06 wrapper', () async {
      final envelope = signEnvelope(payload, keys: rsaKeys());
      envelope.remove('v');

      expect(envelopeVersionOf(envelope), 1);
      expect(envelopePayloadOf(envelope), payload);
      await verifyEnvelope(envelope,
          signerPublicKey: rsaPair.atPublicKey.publicKey);
    });

    test('a version-1 envelope with no signature is refused, not a cast error',
        () async {
      final envelope = signEnvelope(payload, keys: rsaKeys());
      envelope.remove('signature');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a JWS envelope missing its protected header is refused', () async {
      final envelope = rsaJws();
      envelope.remove('protected');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
      expect(() => envelopeSignerOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a JWS payload that does not decode is refused', () {
      final envelope = rsaJws();
      envelope['payload'] = 'not!!!base64url';
      expect(() => envelopePayloadOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));

      envelope['payload'] = b64u('{truncated');
      expect(() => envelopePayloadOf(envelope),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a header whose signed version disagrees with the wrapper is refused',
        () async {
      final envelope = rsaJws();
      envelope['protected'] = b64u('{"alg":"RS256","kid":"enroll-1","v":1}');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message, 'message', contains('the signed claim'))));
    });

    test('the producer refuses what it has no mapping or shape for', () {
      expect(
          () => signEnvelope(payload,
              keys: rsaKeys(),
              hashingAlgo: HashingAlgoType.sha512,
              version: jwsEnvelopeVersion),
          throwsA(isA<ArgumentError>()),
          reason: 'nothing produces RSA under any hash but SHA-256, so the '
              'only RSA mapping is RS256; widen it when a producer exists');
      expect(() => signEnvelope(payload, keys: rsaKeys(), version: 7),
          throwsA(isA<ArgumentError>()));
    });

    test('the producer default is version 1 — nothing on the wire moves', () {
      expect(signEnvelope(payload, keys: rsaKeys())['v'], 1);
    });
  });
}
