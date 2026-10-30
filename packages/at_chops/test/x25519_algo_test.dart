import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('RFC 7748 test vectors', () {
    // The round-trip tests below prove the two sides agree with each other,
    // which they would also do while both wrong. These pin the bytes against
    // the RFC.
    const algo = X25519PureDartAlgo.instance;

    /// The u-coordinate of the base point: the byte 9 followed by 31 zeros.
    final basePoint = Uint8List(32)..[0] = 9;

    // RFC 7748 section 6.1.
    const alicePrivate =
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a';
    const alicePublic =
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a';
    const bobPrivate =
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb';
    const bobPublic =
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f';
    const sharedSecret =
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742';

    test('section 6.1: each private key derives the published public key',
        () async {
      // X25519(a, 9) is the public key, and dh against the base point is
      // exactly that computation.
      expect(_toHex(await algo.dh(_hex(alicePrivate), basePoint)), alicePublic);
      expect(_toHex(await algo.dh(_hex(bobPrivate), basePoint)), bobPublic);
    });

    test('section 6.1: both sides reach the published shared secret', () async {
      expect(_toHex(await algo.dh(_hex(alicePrivate), _hex(bobPublic))),
          sharedSecret);
      expect(_toHex(await algo.dh(_hex(bobPrivate), _hex(alicePublic))),
          sharedSecret);
    });

    // RFC 7748 section 5.2 — raw scalar multiplication, which exercises the
    // clamping and the ladder independently of any key-pair convention.
    for (final v in const [
      (
        scalar:
            'a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4',
        u: 'e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c',
        out: 'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552',
      ),
      (
        scalar:
            '4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d',
        u: 'e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493',
        out: '95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957',
      ),
    ]) {
      test('section 5.2: X25519(${v.scalar.substring(0, 8)}...) matches',
          () async {
        expect(_toHex(await algo.dh(_hex(v.scalar), _hex(v.u))), v.out);
      });
    }
  });

  group('X25519 pure-Dart', () {
    test('DH round-trip: Alice and Bob derive the same shared secret',
        () async {
      final X25519KeyPair alice = await X25519KeyPair.generate();
      final X25519KeyPair bob = await X25519KeyPair.generate();

      final Uint8List alicePub = base64Decode(alice.atPublicKey.publicKey);
      final Uint8List alicePriv = base64Decode(alice.atPrivateKey.privateKey);
      final Uint8List bobPub = base64Decode(bob.atPublicKey.publicKey);
      final Uint8List bobPriv = base64Decode(bob.atPrivateKey.privateKey);

      final algo = X25519PureDartAlgo.instance;
      final Uint8List ss1 = await algo.dh(alicePriv, bobPub);
      final Uint8List ss2 = await algo.dh(bobPriv, alicePub);

      expect(ss1, equals(ss2));
      expect(ss1.length, equals(32));
    });

    test('Generated key pair has 32-byte public and private keys', () async {
      final X25519KeyPair kp = await X25519KeyPair.generate();
      expect(base64Decode(kp.atPublicKey.publicKey).length, equals(32));
      expect(base64Decode(kp.atPrivateKey.privateKey).length, equals(32));
    });
  });
}
