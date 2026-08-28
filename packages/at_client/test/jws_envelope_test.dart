import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, KeyEntryStatus, apskAdvertisement;
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

  String mlDsaApsk() => jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65,
            pub: base64Encode(mlDsaPair.publicKey))
      ]));

  SignedEnvelope rsaEnvelope({String? enrollmentId = 'enroll-1'}) =>
      signEnvelope(payload,
          keys: [rsaKeys()],
          enrollmentId: enrollmentId,
          type: EnvelopeType.app);

  SignedEnvelope mlDsaEnvelope() => signEnvelope(payload,
      keys: [mlDsaKeys()], enrollmentId: 'enroll-pq', type: EnvelopeType.app);

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
          signerPublicKey: rsaPair.atPublicKey.publicKey,
          expecting: EnvelopeType.app);
    });

    test('the protected header is exactly the pinned bytes', () {
      // Raw literal, not built from constants: the signature covers these
      // bytes, so the member ORDER is cryptographically bound.
      expect(unb64u(rsaEnvelope().signature.protected),
          '{"alg":"RS256","typ":"at-app+jws","kid":"enroll-1","v":1}');
    });

    test('a tampered payload fails', () async {
      final envelope =
          rsaEnvelope().withPayloadJson({'hello': 'universe', 'n': 1});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a tampered protected header fails: the claims are signed', () async {
      // Same alg, same v, different kid. The claim is inside the signature,
      // so a relabel cannot go unnoticed.
      final envelope =
          rsaEnvelope().claiming({'alg': 'RS256', 'kid': 'enroll-2', 'v': 1});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
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
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('no algorithm in common'))));
    });

    test('no shared algorithm names BOTH documents, and does not fall back',
        () async {
      // UC-G2.9's case rather than a relabelling: an `_apsk` advertising only
      // RSA, handed an envelope signed under ML-DSA — what a peer that has not
      // taken the transition sees. "No algorithm in common" on its own leaves
      // a reader unable to tell which side is behind, so the message has to
      // name what the envelope carries AND what the advertisement offers.
      await expectLater(
          () => verifyEnvelope(mlDsaEnvelope(),
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()
              .having((e) => e.message, 'message', contains('"ML-DSA-65"'))
              .having((e) => e.message, 'message', contains('"rsa2048"'))));

      // The control, and it is what makes the refusal attributable: the same
      // envelope against an `_apsk` that does advertise ML-DSA verifies. A
      // build that refused every ML-DSA envelope would satisfy the arm above
      // and fail here.
      await verifyEnvelope(mlDsaEnvelope(),
          signerPublicKey: mlDsaApsk(), expecting: EnvelopeType.app);
    });

    test('a corrupted signature fails', () async {
      final original = rsaEnvelope();
      final s = original.signature.signature;
      final envelope = original.withEntryMember(
          'signature', s.replaceRange(0, 1, s[0] == 'A' ? 'B' : 'A'));

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
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
            ...(apskAdvertisement(keys: [
              ApskSigningKey.forPublicKey(
                  alg: SigningAlgoType.rsa2048,
                  pub: rsaPair.atPublicKey.publicKey)
            ])['keys'] as List),
            ...(apskAdvertisement(keys: [
              ApskSigningKey.forPublicKey(
                  alg: SigningAlgoType.mldsa65,
                  pub: base64Encode(mlDsaPair.publicKey))
            ])['keys'] as List),
          ],
        });

    /// One envelope over one payload, signed by both keys — RSA listed FIRST,
    /// so a verifier taking `signatures.first` picks the weaker one.
    ///
    /// Built by the **real writer**, not assembled here. It used to merge two
    /// single-signature envelopes by hand, which made this whole group a test
    /// of the fixture: it would have gone on passing against a writer that
    /// could not emit two signatures at all.
    SignedEnvelope bothSigned() => signEnvelope(payload,
        keys: [rsaKeys(), mlDsaKeys()],
        enrollmentId: 'enroll-1',
        type: EnvelopeType.app);

    test('the writer emits one signature per key, over one payload', () async {
      final envelope = bothSigned();

      expect(envelope.signatures, hasLength(2));
      expect(
          envelope.signatures
              .map((s) => jsonDecode(unb64u(s.protected))['alg'])
              .toList(),
          ['RS256', 'ML-DSA-65'],
          reason: 'one entry per key, in the order the signer listed them');
      expect(envelope.signatures.map((s) => s.kid).toSet(), {'enroll-1'},
          reason: 'every entry names the one signer, which is what lets an '
              'envelope carry several signatures at all');
      expect(envelope.signatures[0].signature,
          isNot(envelope.signatures[1].signature));

      // The property that makes the entries alternatives rather than a chain:
      // one payload member, and each signature covers its own protected header
      // joined to that same text. Re-encoding the payload per key would let
      // two entries sign different bytes and both verify in isolation.
      for (final entry in envelope.signatures) {
        expect(envelope.payloadB64, isNotEmpty);
        expect(entry.protected, isNotEmpty);
      }
      expect(envelope.payload, payload);
    });

    test('the control arm: both signatures valid, and it verifies', () async {
      await verifyEnvelope(bothSigned(),
          signerPublicKey: bothApsk(), expecting: EnvelopeType.app);
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
          () => verifyEnvelope(corrupted,
              signerPublicKey: bothApsk(), expecting: EnvelopeType.app),
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

      await verifyEnvelope(reordered,
          signerPublicKey: bothApsk(), expecting: EnvelopeType.app);

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
            signerPublicKey: bothApsk(),
            expecting: EnvelopeType.app);
      }
    });

    test('and however the ADVERTISEMENT is ordered', () async {
      // The other half of "neither side's ordering alone decides", and the one
      // this group never varied: every arm above publishes `_apsk` with RSA
      // first, so a verifier resolving by the advertisement's order rather
      // than by strength passes all of them.
      String reversedApsk() => jsonEncode({
            'v': 1,
            'keys': ((jsonDecode(bothApsk()) as Map)['keys'] as List)
                .reversed
                .toList(),
          });

      // Control: the untouched envelope verifies under the reversed
      // advertisement at all, so a refusal below is about which algorithm was
      // chosen rather than about the reordering having broken the fixture.
      await verifyEnvelope(bothSigned(),
          signerPublicKey: reversedApsk(), expecting: EnvelopeType.app);

      // Corrupt the RSA entry and leave ML-DSA intact. ML-DSA is the stronger,
      // so it is what gets checked and the corrupt entry is never reached —
      // under BOTH advertisement orderings. Resolving by the advertisement's
      // order instead would refuse the RSA-first one and accept the other.
      final both = bothSigned();
      final rsa = both.signatures.firstWhere((s) => s.alg == 'RS256');
      final corruptRsa = SignedEnvelope.fromJson({
        'payload': both.payloadB64,
        'signatures': [
          {
            'protected': rsa.protected,
            'signature': rsa.signature
                .replaceRange(0, 1, rsa.signature[0] == 'A' ? 'B' : 'A'),
          },
          both.signatures.firstWhere((s) => s.alg != 'RS256').toJson(),
        ],
      });
      for (final apsk in [reversedApsk(), bothApsk()]) {
        await verifyEnvelope(corruptRsa,
            signerPublicKey: apsk, expecting: EnvelopeType.app);
      }
    });

    test('an envelope claiming two different signers is refused', () {
      // The entry that verifies and the entry a caller reads
      // signerEnrollmentId from must be the same entry. Otherwise appending a
      // signature under a stronger algorithm, carrying someone else's kid,
      // makes a caller act on a signer whose signature was never checked.
      final both = bothSigned();
      final impostor = signEnvelope(payload,
          keys: [mlDsaKeys()],
          enrollmentId: 'someone-else',
          type: EnvelopeType.app);

      expect(
          () => SignedEnvelope.fromJson({
                'payload': both.payloadB64,
                'signatures': [
                  both.signatures[0].toJson(),
                  impostor.signature.toJson(),
                ],
              }),
          throwsA(isA<AtSigningVerificationException>()
              .having((e) => e.message, 'message', contains('one signer'))));
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
          '{"alg":"ML-DSA-65","typ":"at-app+jws","kid":"enroll-pq","v":1}');

      await verifyEnvelope(envelope,
          signerPublicKey: mlDsaApsk(), expecting: EnvelopeType.app);
    });

    test('a tampered payload fails', () async {
      final envelope =
          mlDsaEnvelope().withPayloadJson({'hello': 'universe', 'n': 1});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: mlDsaApsk(), expecting: EnvelopeType.app),
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
      expect(unb64u(envelope.signature.protected),
          '{"alg":"RS256","typ":"at-app+jws","v":1}',
          reason: 'a guessed or sentinel id would be frozen inside the '
              'signature where nobody could correct it');
    });

    test('a String payload becomes JSON, so decoding is unconditional', () {
      expect(
          signEnvelope('just text', keys: [rsaKeys()], type: EnvelopeType.app)
              .payload,
          'just text',
          reason: 'what comes out of base64url is JSON, whatever went in');
    });

    test('toJson reproduces what fromJson was given, byte for byte', () {
      // The property the whole shape rests on: the signing input is the
      // RECEIVED characters, so a round trip through the type must not
      // re-encode anything.
      final wire = rsaEnvelope().toJson();
      expect(SignedEnvelope.fromJson(wire).toJson(), wire);
      expect(
          jsonEncode(SignedEnvelope.fromJson(wire).toJson()), jsonEncode(wire));
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
      expect(
          () => rsaEnvelope().claiming(const {}).withEntryMember(
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
      final envelope = rsaEnvelope().claiming({
        'alg': 'RS256',
        // Carried, so the version is what this refusal is about: the type is
        // checked first, and a header that dropped it would be refused before
        // the version was ever read.
        'typ': 'at-app+jws',
        'kid': 'enroll-1',
        'v': 2
      });

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('claims envelope version'))));
    });

    test('a protected header with NO version is refused, naming the absence',
        () async {
      // The other half of the version guard, and the one nothing covered.
      // A released 3.14.0 envelope has no `v` at all, and the reason it never
      // reaches here is that it does not parse — its signature is a flat
      // sibling of the payload rather than an entry in a `signatures` array.
      // This is the same absence arriving in a shape that DOES parse, which
      // is the case a tolerant reader would quietly accept.
      final envelope = rsaEnvelope().claiming({
        'alg': 'RS256',
        // Carried deliberately: the type is checked before the version, so a
        // header that dropped it would be refused for the wrong reason and
        // this test would be green without ever reaching the version.
        'typ': 'at-app+jws',
        'kid': 'enroll-1',
      });

      // The fixture really does omit it. Without this the test passes
      // identically against a `claiming` that quietly kept the version, and
      // the absence it names would never have been on the wire.
      expect(unb64u(envelope.signature.protected), isNot(contains('"v"')));

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message,
              'message',
              // `"null"` specifically, not just the prefix: a reader that had
              // learned to default a missing version to 1 would still satisfy
              // a match on `claims envelope version` alone.
              contains('claims envelope version "null"'))));
    });

    test('the producer refuses a signing algorithm it has no mapping for', () {
      expect(
          () => signEnvelope(payload,
              keys: [
                ApkamSigningKeys(
                    algorithm: SigningAlgoType.ed25519,
                    publicKey: rsaKeys().publicKey,
                    privateKey: rsaKeys().privateKey)
              ],
              type: EnvelopeType.app),
          throwsA(isA<ArgumentError>()),
          reason: 'no envelope signs under Ed25519, and a shape that guessed '
              'an alg name for it would freeze the guess inside a signature');
    });
  });

  group('one algorithm, several advertised keys', () {
    late ({Uint8List publicKey, Uint8List secretKey}) retiredPair;

    setUpAll(() async {
      retiredPair = await MlDsa65PureDartAlgo().generateKeyPair();
    });

    /// What a post-quantum-native enrollment publishes once it mints a signing
    /// key of its own: the new key active, and the ML-DSA APKAM
    /// authentication key it used to sign with kept as `retired`. **Both
    /// entries are mldsa65** — which is the case a verifier taking the first
    /// entry for an algorithm gets wrong.
    String apskWithRetained() => jsonEncode(apskAdvertisement(keys: [
          ApskSigningKey.forPublicKey(
              alg: SigningAlgoType.mldsa65,
              pub: base64Encode(mlDsaPair.publicKey)),
          ApskSigningKey.forPublicKey(
              alg: SigningAlgoType.mldsa65,
              pub: base64Encode(retiredPair.publicKey),
              status: KeyEntryStatus.retired),
        ]));

    test('an envelope signed by the retained key still verifies', () async {
      // The envelope this enrollment signed BEFORE it split authentication
      // from signing. Envelopes are stored durably and verified whenever they
      // are read, so this is not a historical curiosity — it is every record
      // the enrollment wrote up to the moment it minted.
      final envelope = signEnvelope(payload,
          keys: [
            ApkamSigningKeys(
                algorithm: SigningAlgoType.mldsa65,
                publicKey: base64Encode(retiredPair.publicKey),
                privateKey: base64Encode(retiredPair.secretKey))
          ],
          enrollmentId: 'enroll-pq',
          type: EnvelopeType.app);

      await verifyEnvelope(envelope,
          signerPublicKey: apskWithRetained(), expecting: EnvelopeType.app);
    });

    test('and one signed by the current key verifies on the first attempt',
        () async {
      await verifyEnvelope(mlDsaEnvelope(),
          signerPublicKey: apskWithRetained(), expecting: EnvelopeType.app);
    });

    test('a signature under neither key is still refused', () async {
      // Trying every key of the resolved algorithm is not "keep going until
      // something passes": a key this enrollment never published must not
      // verify, or the loop would be an acceptance of anything.
      final stranger = await MlDsa65PureDartAlgo().generateKeyPair();
      final envelope = signEnvelope(payload,
          keys: [
            ApkamSigningKeys(
                algorithm: SigningAlgoType.mldsa65,
                publicKey: base64Encode(stranger.publicKey),
                privateKey: base64Encode(stranger.secretKey))
          ],
          enrollmentId: 'enroll-pq',
          type: EnvelopeType.app);

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: apskWithRetained(), expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message,
              'message',
              contains(
                  'does not verify against any of the 2 mldsa65 key(s)'))));
    });
  });

  group('domain separation: an envelope says what it is for', () {
    test('the type is inside the protected header, under the signature', () {
      final envelope = signEnvelope(payload,
          keys: [rsaKeys()], type: EnvelopeType.chainLink);

      expect(envelope.signature.typ, 'at-chain-link+jws');
      expect(unb64u(envelope.signature.protected),
          contains('"typ":"at-chain-link+jws"'));
      expect(envelope.toJson().keys, isNot(contains('typ')),
          reason: 'a type outside the signature is a claim an attacker can '
              'edit, which is what the version already taught us');
    });

    test('a reader verifying one type refuses an envelope signed for another',
        () async {
      // The signature is perfectly good. That is the point: what fails is the
      // claim that this document is the thing being asked for.
      final envelope =
          signEnvelope(payload, keys: [rsaKeys()], type: EnvelopeType.app);

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.chainLink),
          throwsA(isA<AtSigningVerificationException>().having(
              (e) => e.message,
              'message',
              allOf(
                  contains('"at-app+jws"'), contains('"at-chain-link+jws"')))));

      // Same bytes, same key, asked the right question: it verifies. Without
      // this arm the refusal above would also pass for an envelope that was
      // simply broken.
      await verifyEnvelope(envelope,
          signerPublicKey: rsaPair.atPublicKey.publicKey,
          expecting: EnvelopeType.app);
    });

    test('an untyped header is refused rather than assumed', () async {
      // What an envelope written before this existed looks like. There is no
      // tolerant reading available: assuming a type is the confusion, so the
      // absence has to fail.
      final envelope = rsaEnvelope()
          .claiming({'alg': 'RS256', 'kid': 'enroll-1', 'v': envelopeVersion});

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()
              .having((e) => e.message, 'message', contains('typed nothing'))));
    });

    test('entries that disagree about the type are refused at the boundary',
        () async {
      // Two entries over one payload, typed differently: the entry a verifier
      // resolves is chosen by ALGORITHM, so this document would have the
      // checked entry and the declared purpose be different entries.
      final chainLink = signEnvelope(payload,
          keys: [rsaKeys()], enrollmentId: 'e1', type: EnvelopeType.chainLink);
      final app = signEnvelope(payload,
          keys: [mlDsaKeys()], enrollmentId: 'e1', type: EnvelopeType.app);

      expect(
          () => SignedEnvelope.fromJson({
                'payload': chainLink.payloadB64,
                'signatures': [
                  chainLink.signature.toJson(),
                  app.signature.toJson(),
                ],
              }),
          throwsA(isA<AtSigningVerificationException>().having((e) => e.message,
              'message', contains('signed for one purpose'))));
    });
  });
}
