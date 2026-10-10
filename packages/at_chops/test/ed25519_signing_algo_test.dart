import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for ed25519 signing and verification', () {
    test('Test data signing and verification using generated key pair',
        () async {
      final signingAlgo = Ed25519SigningAlgo();
      final (:publicKey, :secretKey) = await signingAlgo.generateKeyPair();
      final message = Uint8List.fromList('Hello World@123!'.codeUnits);
      final signature =
          await signingAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          signingAlgo.verifyBytes(message,
              signature: signature, publicKey: publicKey),
          completes);
    });
    test('Test data signing and verification - verify with a different key',
        () async {
      final signingAlgo = Ed25519SigningAlgo();
      final (publicKey: _, :secretKey) = await signingAlgo.generateKeyPair();
      final other = await signingAlgo.generateKeyPair();
      final message = Uint8List.fromList('Hello World@123!'.codeUnits);
      final signature =
          await signingAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          signingAlgo.verifyBytes(message,
              signature: signature, publicKey: other.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });
}
