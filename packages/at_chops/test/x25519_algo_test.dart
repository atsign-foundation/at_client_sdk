import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('X25519 pure-Dart', () {
    test('DH round-trip: Alice and Bob derive the same shared secret',
        () async {
      final AtX25519KeyPair alice = await AtChopsUtil.generateX25519KeyPair();
      final AtX25519KeyPair bob = await AtChopsUtil.generateX25519KeyPair();

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
      final AtX25519KeyPair kp = await AtChopsUtil.generateX25519KeyPair();
      expect(base64Decode(kp.atPublicKey.publicKey).length, equals(32));
      expect(base64Decode(kp.atPrivateKey.privateKey).length, equals(32));
    });
  });
}
