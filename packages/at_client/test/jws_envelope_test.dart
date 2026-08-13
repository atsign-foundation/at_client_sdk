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
      algorithm: SigningAlgoType.rsa2048,
      publicKey: rsaPair.atPublicKey.publicKey,
      privateKey: rsaPair.atPrivateKey.privateKey);

  ApkamSigningKeys mlDsaKeys() => ApkamSigningKeys(
      algorithm: SigningAlgoType.mldsa65,
      publicKey: base64Encode(mlDsaPair.publicKey),
      privateKey: base64Encode(mlDsaPair.secretKey));

  String mlDsaApsk() => jsonEncode(apskAdvertisement(
      apkamPublicKey: base64Encode(mlDsaPair.publicKey),
      signingAlgo: SigningAlgoType.mldsa65));

  SignedEnvelope rsaEnvelope({String? enrollmentId = 'enroll-1'}) =>
      signEnvelope(payload, keys: rsaKeys(), enrollmentId: enrollmentId);

  SignedEnvelope mlDsaEnvelope() =>
      signEnvelope(payload, keys: mlDsaKeys(), enrollmentId: 'enroll-pq');

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
      // Relabelling the one signature as ML-DSA leaves the envelope with
      // nothing the RSA-only _apsk can check: the claim does not select the
      // routine, and the verifier does not quietly fall back to trying the RSA
      // key against an entry that says it is not RSA.
      final envelope = rsaEnvelope()
          .claiming({'alg': 'ML-DSA-65', 'kid': 'enroll-1', 'v': 1});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('no algorithm in common'))));
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

  group('UC-G1.7 · the verifier takes the strongest and does not fall back',
      () {
    /// An `_apsk` advertising both signing keys of one enrollment — the shape
    /// a rollout-2 enrollment publishes.
    String bothApsk() => jsonEncode({
          'v': 1,
          'keys': [
            ...(apskAdvertisement(
                apkamPublicKey: rsaPair.atPublicKey.publicKey,
                signingAlgo: SigningAlgoType.rsa2048)['keys'] as List),
            ...(apskAdvertisement(
                apkamPublicKey: base64Encode(mlDsaPair.publicKey),
                signingAlgo: SigningAlgoType.mldsa65)['keys'] as List),
          ],
        });

    /// One envelope over one payload, signed by both keys — RSA listed FIRST,
    /// so a verifier taking `signatures.first` picks the weaker one.
    SignedEnvelope bothSigned() {
      final rsa =
          signEnvelope(payload, keys: rsaKeys(), enrollmentId: 'enroll-1');
      final mlDsa =
          signEnvelope(payload, keys: mlDsaKeys(), enrollmentId: 'enroll-1');
      return SignedEnvelope.fromJson({
        'payload': rsa.payloadB64,
        'signatures': [
          rsa.signature.toJson(),
          mlDsa.signature.toJson(),
        ],
      });
    }

    test('the control arm: both signatures valid, and it verifies', () async {
      await verifyEnvelope(bothSigned(), signerPublicKey: bothApsk());
    });

    test('a valid RSA signature does NOT rescue a corrupt ML-DSA one',
        () async {
      // The row itself. Falling through to the signature that happens to check
      // out hands the choice of algorithm to whoever tampered with the
      // envelope, and reads as success in every log.
      final both = bothSigned();
      final ml = both.signatures[1];
      final corrupted = SignedEnvelope.fromJson({
        'payload': both.payloadB64,
        'signatures': [
          both.signatures[0].toJson(),
          {
            'protected': ml.protected,
            'signature': ml.signature
                .replaceRange(0, 1, ml.signature[0] == 'A' ? 'B' : 'A'),
          },
        ],
      });

      await expectLater(
          () => verifyEnvelope(corrupted, signerPublicKey: bothApsk()),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('mldsa65 signature does not verify'))),
          reason: 'the refusal must name ML-DSA — a message naming RSA would '
              'mean the weaker entry was the one checked');
    });

    test('and the strongest is chosen however the entries are ordered',
        () async {
      // RSA is listed first above. Pinning only that order would pass on a
      // reader that simply took the LAST entry.
      final both = bothSigned();
      final reordered = SignedEnvelope.fromJson({
        'payload': both.payloadB64,
        'signatures': [
          both.signatures[1].toJson(),
          both.signatures[0].toJson(),
        ],
      });

      await verifyEnvelope(reordered, signerPublicKey: bothApsk());

      // Corrupt the RSA entry in each ordering: the verdict must not change,
      // because RSA is never the entry checked when ML-DSA is on offer.
      for (final entries in [
        [both.signatures[1], both.signatures[0]],
        [both.signatures[0], both.signatures[1]],
      ]) {
        final rsa = entries.firstWhere((s) => s.alg == 'RS256');
        final other = entries.firstWhere((s) => s.alg != 'RS256');
        await verifyEnvelope(
            SignedEnvelope.fromJson({
              'payload': both.payloadB64,
              'signatures': [
                for (final s in entries)
                  if (identical(s, rsa))
                    {
                      'protected': rsa.protected,
                      'signature': rsa.signature.replaceRange(
                          0, 1, rsa.signature[0] == 'A' ? 'B' : 'A'),
                    }
                  else
                    other.toJson()
              ],
            }),
            signerPublicKey: bothApsk());
      }
    });

    test('an envelope claiming two different signers is refused', () {
      // The entry that verifies and the entry a caller reads
      // signerEnrollmentId from must be the same entry. Otherwise appending a
      // signature under a stronger algorithm, carrying someone else's kid,
      // makes a caller act on a signer whose signature was never checked.
      final both = bothSigned();
      final impostor =
          signEnvelope(payload, keys: mlDsaKeys(), enrollmentId: 'someone-else');

      expect(
          () => SignedEnvelope.fromJson({
                'payload': both.payloadB64,
                'signatures': [
                  both.signatures[0].toJson(),
                  impostor.signature.toJson(),
                ],
              }),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message, 'message', contains('one signer'))));
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
              keys: ApkamSigningKeys(
                  algorithm: SigningAlgoType.ed25519,
                  publicKey: rsaKeys().publicKey,
                  privateKey: rsaKeys().privateKey)),
          throwsA(isA<ArgumentError>()),
          reason: 'no envelope signs under Ed25519, and a shape that guessed '
              'an alg name for it would freeze the guess inside a signature');
    });
  });
}
