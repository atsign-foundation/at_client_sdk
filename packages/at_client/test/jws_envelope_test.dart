import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show apskAdvertisement;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

import 'test_utils/envelope_tamper.dart';

/// The signed-envelope shape: RFC 7515 **General** JSON Serialization,
/// `{payload, signatures: [{protected, signature}]}`, with `{alg, kid, v}`
/// inside each protected header, modelled by [SignedEnvelope].
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

  SignedEnvelope rsaEnvelope({String? enrollmentId = 'enroll-1'}) =>
      signEnvelope(payload, keys: rsaKeys(), enrollmentId: enrollmentId);

  SignedEnvelope mlDsaEnvelope() => signEnvelope(payload,
      keys: mlDsaKeys(),
      enrollmentId: 'enroll-pq',
      signingAlgo: SigningAlgoType.mldsa65);

  group('the envelope shape, RSA arm', () {
    test('signs, verifies, and survives the base64 padding trap', () async {
      final envelope = rsaEnvelope();

      expect(envelope.toJson().keys.toList(), ['payload', 'signatures']);
      expect(envelope.signatures, hasLength(1));
      expect(envelope.signature.toJson().keys.toList(),
          ['protected', 'signature']);
      for (final text in [
        envelope.payloadB64,
        envelope.signature.protected,
        envelope.signature.signature,
      ]) {
        expect(text.contains('='), isFalse,
            reason: 'RFC 7515 base64url is unpadded');
      }
      // The measured trap: 256 signature bytes → 342 unpadded chars, a length
      // the naive decode throws on. Assert the length so this test can never
      // silently stop covering the throwing case.
      final signature = envelope.signature.signature;
      expect(signature.length, 342);
      expect(() => base64Decode(signature), throwsA(isA<FormatException>()),
          reason: 'if this stops throwing, the padding trap this arm exists '
              'to cover has moved');

      await verifyEnvelope(envelope,
          signerPublicKey: rsaPair.atPublicKey.publicKey);
    });

    test('the protected header is exactly the pinned bytes', () {
      // Raw literal, not built from constants: the signature covers these
      // bytes, so the member ORDER is cryptographically bound.
      expect(unb64u(rsaEnvelope().signature.protected),
          '{"alg":"RS256","kid":"enroll-1","v":1}');
    });

    test('a tampered payload fails', () async {
      final envelope =
          rsaEnvelope().withPayloadJson({'hello': 'universe', 'n': 1});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a tampered protected header fails: the claims are signed', () async {
      // Same alg, same v, different kid. The claim is inside the signature,
      // so a relabel cannot go unnoticed.
      final envelope = rsaEnvelope()
          .claiming({'alg': 'RS256', 'kid': 'enroll-2', 'v': 1});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test("alg cannot overrule the published key's declaration", () async {
      final envelope = rsaEnvelope()
          .claiming({'alg': 'ML-DSA-65', 'kid': 'enroll-1', 'v': 1});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message, 'message', contains('refusing the mismatch'))));
    });

    test('a corrupted signature fails', () async {
      final original = rsaEnvelope();
      final s = original.signature.signature;
      final envelope = original.withEntryMember(
          'signature', s.replaceRange(0, 1, s[0] == 'A' ? 'B' : 'A'));

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('the envelope shape, ML-DSA arm', () {
    test('signs and verifies under the array _apsk', () async {
      final envelope = mlDsaEnvelope();

      final signature = envelope.signature.signature;
      expect(signature.length, 4412,
          reason: 'ML-DSA-65 is 3309 signature bytes — and 4412 % 4 == 0, so '
              'this arm alone can NEVER catch a missing base64 '
              'normalisation; that is what the RSA arm is for');
      expect(signature.contains('='), isFalse);
      expect(unb64u(envelope.signature.protected),
          '{"alg":"ML-DSA-65","kid":"enroll-pq","v":1}');

      await verifyEnvelope(envelope, signerPublicKey: mlDsaApsk());
    });

    test('a tampered payload fails', () async {
      final envelope =
          mlDsaEnvelope().withPayloadJson({'hello': 'universe', 'n': 1});

      await expectLater(
          () => verifyEnvelope(envelope, signerPublicKey: mlDsaApsk()),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('reading an envelope', () {
    test('payload decodes what the raw member cannot give you', () {
      final envelope = rsaEnvelope();

      expect(envelope.payloadB64, isA<String>(),
          reason: 'the raw member is base64url text, never the payload');
      expect(envelope.payload, payload);
    });

    test('the header exposes alg, kid and version', () {
      final entry = rsaEnvelope().signature;

      expect(entry.alg, 'RS256');
      expect(entry.kid, 'enroll-1');
      expect(entry.version, envelopeVersion);
    });

    test('signerEnrollmentId reads the kid claim', () {
      expect(rsaEnvelope().signerEnrollmentId, 'enroll-1');
    });

    test('no enrollment, no claim — and no kid member at all', () {
      final envelope = rsaEnvelope(enrollmentId: null);

      expect(envelope.signerEnrollmentId, isNull);
      expect(unb64u(envelope.signature.protected), '{"alg":"RS256","v":1}',
          reason: 'a guessed or sentinel id would be frozen inside the '
              'signature where nobody could correct it');
    });

    test('a String payload becomes JSON, so decoding is unconditional', () {
      expect(signEnvelope('just text', keys: rsaKeys()).payload, 'just text',
          reason: 'what comes out of base64url is JSON, whatever went in');
    });

    test('toJson reproduces what fromJson was given, byte for byte', () {
      // The property the whole shape rests on: the signing input is the
      // RECEIVED characters, so a round trip through the type must not
      // re-encode anything.
      final wire = rsaEnvelope().toJson();
      expect(SignedEnvelope.fromJson(wire).toJson(), wire);
      expect(jsonEncode(SignedEnvelope.fromJson(wire).toJson()),
          jsonEncode(wire));
    });
  });

  group('refusals', () {
    test('an envelope with no signatures array is refused, not a cast error',
        () {
      final json = rsaEnvelope().toJson()..remove('signatures');

      expect(() => SignedEnvelope.fromJson(json),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('an empty signatures array is refused, not treated as unsigned', () {
      // The arm that matters: an envelope nobody signed must not verify
      // vacuously by having nothing to check.
      expect(
          () => SignedEnvelope.fromJson(rsaEnvelope().withRawSignatures([])),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('non-empty signatures array'))));
    });

    test('a signatures entry that is not an object is refused', () {
      expect(
          () => SignedEnvelope.fromJson(
              rsaEnvelope().withRawSignatures(['not-an-object'])),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('an entry missing its protected header is refused', () {
      final envelope = rsaEnvelope();
      expect(
          () => SignedEnvelope.fromJson(envelope.withRawSignatures([
                {'signature': envelope.signature.signature}
              ])),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a non-string payload is refused', () {
      expect(
          () => SignedEnvelope.fromJson(
              {...rsaEnvelope().toJson(), 'payload': 42}),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a protected header that is not JSON is refused at parse', () {
      // At parse, not at read: an entry whose header cannot be read is not an
      // entry, and nothing downstream should have to re-check it.
      expect(() => rsaEnvelope().claiming(const {}).withEntryMember(
          'protected', b64u('{truncated')),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a payload that does not decode is refused at READ, not at parse', () {
      // The other side of that line: a payload is only decoded by whoever
      // wants it, so a bad one is not a malformed envelope.
      final envelope = rsaEnvelope().withPayload('not!!!base64url');
      expect(() => envelope.payload,
          throwsA(isA<AtSigningVerificationException>()));

      expect(() => rsaEnvelope().withPayload(b64u('{truncated')).payload,
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a protected header naming another version is refused', () async {
      // The version is inside the signature, so this is not a tamper defence
      // — it is what stops a future shape being read as this one by a build
      // that has no code for it.
      final envelope =
          rsaEnvelope().claiming({'alg': 'RS256', 'kid': 'enroll-1', 'v': 2});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('claims envelope version'))));
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
