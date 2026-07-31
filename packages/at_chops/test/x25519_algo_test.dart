import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('X25519 pure-Dart', () {
    final algo = X25519PureDartAlgo.instance;

    test('DH round-trip: Alice and Bob derive the same shared secret',
        () async {
      final alice = await algo.generateKeyPair();
      final bob = await algo.generateKeyPair();

      final Uint8List ss1 = await algo.dh(alice.privateKey, bob.publicKey);
      final Uint8List ss2 = await algo.dh(bob.privateKey, alice.publicKey);

      expect(ss1, equals(ss2));
      expect(ss1.length, equals(32));
    });

    test('Generated key pair has 32-byte public and private keys', () async {
      final kp = await algo.generateKeyPair();
      expect(kp.publicKey.length, equals(32));
      expect(kp.privateKey.length, equals(32));
    });
  });
}
