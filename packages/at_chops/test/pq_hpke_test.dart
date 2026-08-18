import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

import 'x_wing_test_vectors.dart';

/// The empty binding, for tests whose subject is something other than `info`
/// (tampering, malformed envelopes, wrong-length keys). `pqSeal`/`pqOpen`
/// require `info` so that no caller can share a binding by saying nothing;
/// these say `_noInfo` explicitly instead.
final Uint8List _noInfo = Uint8List(0);

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
  Uint8List newSeed() => throw UnsupportedError('not used in this test');
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> keyPairFromSeed(
          Uint8List seed) async =>
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

      final envelope = await pqSeal(xwing, kp.publicKey, pt, info: _noInfo);
      final opened = await pqOpen(xwing, kp.secretKey, envelope, info: _noInfo);

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
      final envelope =
          await pqSeal(xwing, kp.publicKey, Uint8List(0), info: _noInfo);
      expect(
          await pqOpen(xwing, kp.secretKey, envelope, info: _noInfo), isEmpty);
    });
  });

  group('pqOpen rejects tampering', () {
    late Uint8List goodEnvelope;
    late ({Uint8List publicKey, Uint8List secretKey}) kp;
    final pt = _utf8('tamper target');

    setUp(() async {
      kp = await xwing.generateKeyPair();
      goodEnvelope = await pqSeal(xwing, kp.publicKey, pt, info: _noInfo);
    });

    test('flipped AEAD ciphertext byte → authFailure', () async {
      final bad = Uint8List.fromList(goodEnvelope);
      // 3 = header (ver + ctLen), then skip KEM ciphertext to reach the GCM body.
      bad[3 + XWingPureDartAlgo.ciphertextLength] ^= 0x01;
      expect(() => pqOpen(xwing, kp.secretKey, bad, info: _noInfo),
          _opensWith(PqOpenFailure.authFailure));
    });

    test('flipped tag byte → authFailure', () async {
      final bad = Uint8List.fromList(goodEnvelope);
      bad[bad.length - 1] ^= 0x01; // last byte of the 16-byte tag
      expect(() => pqOpen(xwing, kp.secretKey, bad, info: _noInfo),
          _opensWith(PqOpenFailure.authFailure));
    });

    test('flipped KEM ciphertext byte → authFailure', () async {
      final bad = Uint8List.fromList(goodEnvelope);
      bad[3] ^= 0x01; // implicit-rejection KEM → different ss → AEAD fails
      expect(() => pqOpen(xwing, kp.secretKey, bad, info: _noInfo),
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
          info: _noInfo, aad: _utf8('aad-seal'));
      expect(() => pqOpen(xwing, kp.secretKey, envelope,
              info: _noInfo, aad: _utf8('aad-open')),
          _opensWith(PqOpenFailure.authFailure));
    });
  });

  group('pqOpen rejects malformed envelopes', () {
    test('unsupported version → versionMismatch', () async {
      final kp = await xwing.generateKeyPair();
      final envelope = await pqSeal(
          xwing, kp.publicKey, _utf8('payload'), info: _noInfo);
      // 0xff rather than 0x02: 0x02 is RFC 9180 and is now supported, so using
      // it here would test the AEAD rather than the version check.
      final bad = Uint8List.fromList(envelope)..[0] = 0xff;
      expect(() => pqOpen(xwing, kp.secretKey, bad, info: _noInfo),
          _opensWith(PqOpenFailure.versionMismatch));
    });

    test('shorter than header → malformedEnvelope', () async {
      expect(
          () => pqOpen(xwing, XWingVector1.seed, Uint8List(2), info: _noInfo),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });

    test('declared ctLen overruns envelope → malformedEnvelope', () async {
      // ver=0x02, ctLen=0xffff, but only a few bytes follow. The version
      // just has to be one this build supports, or the version check fires
      // first and the framing is never reached.
      final bad = Uint8List.fromList([0x02, 0xff, 0xff, 1, 2, 3, 4, 5, 6, 7]);
      expect(() => pqOpen(xwing, XWingVector1.seed, bad, info: _noInfo),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });

    test('a KEM ciphertext of the wrong length → malformedEnvelope', () async {
      // Well-formed header, valid secret key, but a KEM ciphertext the KEM
      // itself rejects. This reaches decapsulate, which raises an ArgumentError
      // — and a caller told to catch PqOpenException would otherwise get an
      // uncaught error on nothing worse than a bad input.
      final ctLen = 8;
      final bad = Uint8List.fromList(
          [0x02, 0x00, ctLen, ...List.filled(ctLen + 16 + 4, 0)]);
      expect(() => pqOpen(xwing, XWingVector1.seed, bad, info: _noInfo),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });

    test('a secret key of the wrong length → malformedEnvelope', () async {
      final kp = await xwing.generateKeyPair();
      final envelope = await pqSeal(
          xwing, kp.publicKey, _utf8('payload'), info: _noInfo);
      expect(() => pqOpen(xwing, Uint8List(7), envelope, info: _noInfo),
          _opensWith(PqOpenFailure.malformedEnvelope));
    });
  });

  group('pqSeal rejects caller misuse', () {
    test('a public key of the wrong length → PqSealException', () async {
      // The mirror of pqOpen's wrong-length secret key above. PqSealException's
      // own dartdoc gives this as its example, and for a while it was the one
      // case that escaped raw: pqSeal called encapsulate unwrapped, so callers
      // catching the documented type got an ArgumentError instead. Recipient
      // public keys arrive from a peer's advertisement on every path that
      // reaches pqSeal, so this is reachable input rather than a typo.
      await expectLater(
          pqSeal(xwing, Uint8List(7), _utf8('payload'), info: _noInfo),
          throwsA(isA<PqSealException>()));
    });
  });

  group('known-answer vectors (byte-exact)', () {
    // The golden envelope is pinned to lock the ENVELOPE FRAMING
    // (ver || ctLen || kemCt || body) against accidental drift. The key
    // schedule inside it is RFC 9180's and is pinned separately, and better,
    // by the working group's own vectors in rfc9180_hpke_test.dart. To
    // regenerate after an intentional construction change, seal with a
    // _FixedKem double (see below) and print the envelope hex.

    test('fixed-KEM construction KAT: seal is deterministic + opens', () async {
      final ss = Uint8List.fromList(List<int>.generate(32, (i) => i)); // [0x00..0x1f]
      final ct = fromHex('aabbccddeeff0011');
      final pt = _utf8('hpke-style seal KAT v1');
      final info = _utf8('kat-info');
      final aad = _utf8('kat-aad');

      const goldenHex =
          '020008aabbccddeeff0011970d4ed3fadb16aed84c9352c9eb630ba40407775f'
          'b373a3e8fce05c3b788f6a941f3b172527';

      // _FixedKem ignores both keys — any value is valid here.
      final envelope = await pqSeal(_FixedKem(ss, ct), Uint8List(0), pt,
          info: info, aad: aad);
      expect(toHex(envelope), equals(goldenHex));

      final opened = await pqOpen(_FixedKem(ss, ct), Uint8List(0), envelope,
          info: info, aad: aad);
      expect(opened, equals(pt));
    });

    test('X-Wing end-to-end KAT: the published ct opens with the real KEM',
        () async {
      // Sealed through a _FixedKem pinned to the published vector's (ss, ct),
      // then opened with the REAL XWingPureDartAlgo and the published seed.
      // That is the whole assertion: the open only succeeds if
      // decapsulate(seed, ct) reproduces expectedSs, because the AEAD key
      // derives from it.
      //
      // This replaced a hand-composed golden envelope when `0x01` was retired.
      // The golden could not simply be re-pinned: pqSeal takes its ciphertext
      // from the KEM, which is randomised, so the old value had been assembled
      // by hand. Driving it through _FixedKem asserts the same property
      // without anyone hand-rolling an envelope, and asserts it against the
      // real decapsulation rather than against bytes we wrote down.
      final pt = _utf8('x-wing end-to-end KAT');
      final info = _utf8('xwing-kat-info');
      final aad = _utf8('xwing-kat-aad');

      final envelope = await pqSeal(
          _FixedKem(XWingVector1.expectedSs, XWingVector1.ct), Uint8List(0), pt,
          info: info, aad: aad);

      // sanity: kemCt slice equals the published X-Wing vector ciphertext.
      expect(
          toHex(Uint8List.sublistView(envelope, 3, 3 + XWingVector1.ct.length)),
          equals(toHex(XWingVector1.ct)));

      final opened = await pqOpen(xwing, XWingVector1.seed, envelope,
          info: info, aad: aad);
      expect(opened, equals(pt));
    });
  });
}
