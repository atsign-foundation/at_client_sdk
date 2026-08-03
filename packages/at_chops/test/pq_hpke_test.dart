import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

import 'x_wing_test_vectors.dart';

/// Fixed-output KEM double — makes [pqSeal] deterministic so the seal
/// construction can be pinned byte-exact, independent of the (randomised) real
/// X-Wing KEM.
final class _FixedKem implements AtKemAlgorithm {
  final Uint8List _ss;
  final Uint8List _ct;
  _FixedKem(this._ss, this._ct);
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async =>
      throw UnsupportedError('not used in this test');
  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
          Uint8List publicKey) async =>
      (ciphertext: _ct, sharedSecret: _ss);
  @override
  Future<Uint8List> decapsulate(
          Uint8List secretKey, Uint8List ciphertext) async =>
      _ss;
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Matcher _opensWith(PqOpenFailure reason) => throwsA(isA<PqOpenException>()
    .having((e) => e.reason, 'reason', reason));

void main() {
  final xwing = XWingPureDartAlgo.instance;

  group('pqSeal/pqOpen round-trip', () {
    test('random keypair, with info + aad', () async {
      final kp = await xwing.generateKeyPair();
      final pt = _utf8('the quick brown fox 🦊');
      final info = _utf8('context-A');
      final aad = _utf8('header-bytes');

      final envelope =
          await pqSeal(xwing, kp.publicKey, pt, info: info, aad: aad);
      final opened =
          await pqOpen(xwing, kp.secretKey, envelope, info: info, aad: aad);

      expect(opened, equals(pt));
    });

    test('random keypair, no info/aad', () async {
      final kp = await xwing.generateKeyPair();
      final pt = _utf8('no-context payload');

      final envelope = await pqSeal(xwing, kp.publicKey, pt);
      final opened = await pqOpen(xwing, kp.secretKey, envelope);

      expect(opened, equals(pt));
    });

    test('vector-seeded keypair round-trips', () async {
      final kp = await xwing.generateKeyPair(XWingVector1.seed);
      final pt = _utf8('sealed to a spec-vector keypair');
      final info = _utf8('context-A');

      final envelope = await pqSeal(xwing, kp.publicKey, pt, info: info);
      final opened = await pqOpen(xwing, kp.secretKey, envelope, info: info);

      expect(opened, equals(pt));
    });

    test('empty plaintext round-trips', () async {
      final kp = await xwing.generateKeyPair();
      final envelope = await pqSeal(xwing, kp.publicKey, Uint8List(0));
      expect(await pqOpen(xwing, kp.secretKey, envelope), isEmpty);
    });
  });

  group('pqOpen rejects tampering', () {
    late Uint8List goodEnvelope;
    late ({Uint8List publicKey, Uint8List secretKey}) kp;
    final pt = _utf8('tamper target');

    setUp(() async {
      kp = await xwing.generateKeyPair();
      goodEnvelope = await pqSeal(xwing, kp.publicKey, pt);
    });

    test('flipped AEAD ciphertext byte → authFailure', () async {
      final bad = Uint8List.fromList(goodEnvelope);
      // 3 = header (ver + ctLen), then skip KEM ciphertext to reach the GCM body.
      bad[3 + XWingPureDartAlgo.ciphertextLength] ^= 0x01;
      expect(() => pqOpen(xwing, kp.secretKey, bad),
          _opensWith(PqOpenFailure.authFailure));
    });

    test('flipped tag byte → authFailure', () async {
      final bad = Uint8List.fromList(goodEnvelope);
      bad[bad.length - 1] ^= 0x01; // last byte of the 16-byte tag
      expect(() => pqOpen(xwing, kp.secretKey, bad),
          _opensWith(PqOpenFailure.authFailure));
    });

    test('flipped KEM ciphertext byte → authFailure', () async {
      final bad = Uint8List.fromList(goodEnvelope);
      bad[3] ^= 0x01; // implicit-rejection KEM → different ss → AEAD fails
      expect(() => pqOpen(xwing, kp.secretKey, bad),
          _opensWith(PqOpenFailure.authFailure));
    });
  });

  group('pqOpen rejects context mismatch', () {
    test('info mismatch → authFailure', () async {
      final kp = await xwing.generateKeyPair();
      final envelope = await pqSeal(xwing, kp.publicKey, _utf8('payload'),
          info: _utf8('context-seal'));
      expect(() => pqOpen(xwing, kp.secretKey, envelope, info: _utf8('context-open')),
          _opensWith(PqOpenFailure.authFailure));
    });

    test('aad mismatch → authFailure', () async {
      final kp = await xwing.generateKeyPair();
      final envelope = await pqSeal(xwing, kp.publicKey, _utf8('payload'),
          aad: _utf8('aad-seal'));
      expect(() => pqOpen(xwing, kp.secretKey, envelope, aad: _utf8('aad-open')),
          _opensWith(PqOpenFailure.authFailure));
    });
  });

  group('pqOpen rejects malformed envelopes', () {
    test('unsupported version → versionMismatch', () async {
      final kp = await xwing.generateKeyPair();
      final envelope = await pqSeal(xwing, kp.publicKey, _utf8('payload'));
      final bad = Uint8List.fromList(envelope)..[0] = 0x02;
      expect(() => pqOpen(xwing, kp.secretKey, bad),
          _opensWith(PqOpenFailure.versionMismatch));
    });

    test('shorter than header → malformedEnvelope', () async {
      expect(() => pqOpen(xwing, XWingVector1.seed, Uint8List(2)),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });

    test('declared ctLen overruns envelope → malformedEnvelope', () async {
      // ver=0x01, ctLen=0xffff, but only a few bytes follow.
      final bad = Uint8List.fromList([0x01, 0xff, 0xff, 1, 2, 3, 4, 5, 6, 7]);
      expect(() => pqOpen(xwing, XWingVector1.seed, bad),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });

    test('a KEM ciphertext of the wrong length → malformedEnvelope', () async {
      // Well-formed header, valid secret key, but a KEM ciphertext the KEM
      // itself rejects. This reaches decapsulate, which raises an ArgumentError
      // — and a caller told to catch PqOpenException would otherwise get an
      // uncaught error on nothing worse than a bad input.
      final ctLen = 8;
      final bad = Uint8List.fromList(
          [0x01, 0x00, ctLen, ...List.filled(ctLen + 16 + 4, 0)]);
      expect(() => pqOpen(xwing, XWingVector1.seed, bad),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });

    test('a secret key of the wrong length → malformedEnvelope', () async {
      final kp = await xwing.generateKeyPair();
      final envelope = await pqSeal(xwing, kp.publicKey, _utf8('payload'));
      expect(() => pqOpen(xwing, Uint8List(7), envelope),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });
  });

  group('known-answer vectors (byte-exact)', () {
    // Golden envelopes are pinned, computed once by composing the
    // already-vector-verified HkdfSha256 + AesGcm256EncryptionAlgo. They lock
    // the seal construction (HKDF key schedule + AES-256-GCM body) against
    // accidental drift. To regenerate after an intentional construction change,
    // seal with a _FixedKem double (see below) and print the envelope hex.

    test('fixed-KEM construction KAT: seal is deterministic + opens', () async {
      final ss = Uint8List.fromList(List<int>.generate(32, (i) => i)); // [0x00..0x1f]
      final ct = fromHex('aabbccddeeff0011');
      final pt = _utf8('hpke-style seal KAT v1');
      final info = _utf8('kat-info');
      final aad = _utf8('kat-aad');

      const goldenHex =
          '010008aabbccddeeff0011bc05df489e9772f4f4afd413e0a05318e3b5b989d2'
          '29f909f3607bf9731afb4988c8bd5608bc';

      // _FixedKem ignores both keys — any value is valid here.
      final envelope = await pqSeal(_FixedKem(ss, ct), Uint8List(0), pt,
          info: info, aad: aad);
      expect(toHex(envelope), equals(goldenHex));

      final opened = await pqOpen(_FixedKem(ss, ct), Uint8List(0), envelope,
          info: info, aad: aad);
      expect(opened, equals(pt));
    });

    test('X-Wing end-to-end KAT: open spec-vector envelope', () async {
      // Envelope = ver || ctLen || XWingVector1.ct || AEAD(body), where the
      // AEAD key/nonce derive from the vector's expected shared secret. Opening
      // it drives real XWingPureDartAlgo.decapsulate(seed, ct) → expectedSs.
      const goldenHex = '010460'
          'b83aa828d4d62b9a83ceffe1d3d3bb1ef31264643c070c5798927e41fb07914a'
          '273f8f96e7826cd5375a283d7da885304c5de0516a0f0654243dc5b97f8bfeb8'
          '31f68251219aabdd723bc6512041acbaef8af44265524942b902e68ffd23221c'
          'da70b1b55d776a92d1143ea3a0c475f63ee6890157c7116dae3f62bf72f60acd'
          '2bb8cc31ce2ba0de364f52b8ed38c79d719715963a5dd3842d8e8b43ab704e47'
          '59b5327bf027c63c8fa857c4908d5a8a7b88ac7f2be394d93c3706ddd4e698cc'
          '6ce370101f4d0213254238b4a2e8821b6e414a1cf20f6c1244b699046f5a01ca'
          'a0a1a55516300b40d2048c77cc73afba79afeea9d2c0118bdf2adb8870dc328c'
          '5516cc45b1a2058141039e2c90a110a9e16b318dfb53bd49a126d6b73f215787'
          '517b8917cc01cabd107d06859854ee8b4f9861c226d3764c87339ab16c3667d2'
          'f49384e55456dd40414b70a6af841585f4c90c68725d57704ee8ee7ce6e2f9be'
          '582dbee985e038ffc346ebfb4e22158b6c84374a9ab4a44e1f91de5aac5197f8'
          '9bc5e5442f51f9a5937b102ba3beaebf6e1c58380a4a5fedce4a4e5026f88f52'
          '8f59ffd2db41752b3a3d90efabe463899b7d40870c530c8841e8712b733668ed'
          '033adbfafb2d49d37a44d4064e5863eb0af0a08d47b3cc888373bc05f7a33b84'
          '1bc2587c57eb69554e8a3767b7506917b6b70498727f16eac1a36ec8d8cfaf75'
          '1549f2277db277e8a55a9a5106b23a0206b4721fa9b3048552c5bd5b594d6e24'
          '7f38c18c591aea7f56249c72ce7b117afcc3a8621582f9cf71787e183dee0936'
          '7976e98409ad9217a497df888042384d7707a6b78f5f7fb8409e3b5351753734'
          '61b776002d799cbad62860be70573ecbe13b246e0da7e93a52168e0fb6a9756b'
          '895ef7f0147a0dc81bfa644b088a9228160c0f9acf1379a2941cd28c06ebc80e'
          '44e17aa2f8177010afd78a97ce0868d1629ebb294c5151812c583daeb8868522'
          '0f4da9118112e07041fcc24d5564a99fdbde28869fe0722387d7a9a4d16e1cc8'
          '555917e09944aa5ebaaaec2cf62693afad42a3f518fce67d273cc6c9fb5472b3'
          '80e8573ec7de06a3ba2fd5f931d725b493026cb0acbd3fe62d00e4c790d965d7'
          'a03a3c0b4222ba8c2a9a16e2ac658f572ae0e746eafc4feba023576f08942278'
          'a041fb82a70a595d5bacbf297ce2029898a71e5c3b0d1c6228b485b1ade509b3'
          '5fbca7eca97b2132e7cb6bc465375146b7dceac969308ac0c2ac89e7863eb894'
          '3015b24314cafb9c7c0e85fe543d56658c213632599efabfc1ec49dd8c88547b'
          'b2cc40c9d38cbd3099b4547840560531d0188cd1e9c23a0ebee0a03d5577d66b'
          '1d2bcb4baaf21cc7fef1e03806ca96299df0dfbc56e1b2b43e4fc20c37f834c4'
          'af62127e7dae86c3c25a2f696ac8b589dec71d595bfbe94b5ed4bc07d800b330'
          '796fda89edb77be0294136139354eb8cd37591578f9c600dd9be8ec6219fdd50'
          '7adf3397ed4d68707b8d13b24ce4cd8fb22851bfe9d632407f31ed6f7cb1600d'
          'e56f17576740ce2a32fc5145030145cfb97e63e0e41d354274a079d3e6fb2e15'
          'e98b9f949b3fd7ac46409929b534041096d59e43504fcccebc3648f104308a21'
          '283ef973b7';

      final envelope = fromHex(goldenHex);
      // sanity: kemCt slice equals the published X-Wing vector ciphertext.
      expect(toHex(Uint8List.sublistView(envelope, 3, 3 + XWingVector1.ct.length)),
          equals(toHex(XWingVector1.ct)));

      final opened = await pqOpen(xwing, XWingVector1.seed, envelope,
          info: _utf8('xwing-kat-info'), aad: _utf8('xwing-kat-aad'));
      expect(opened, equals(_utf8('x-wing end-to-end KAT')));
    });
  });
}
