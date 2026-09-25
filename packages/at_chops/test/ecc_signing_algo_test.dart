import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for ecc signing and verification', () {
    test('Test ecc signing and verification using generated key pair',
        () async {
      final eccAlgo = EccSigningAlgo();
      final (:publicKey, :secretKey) = await eccAlgo.generateKeyPair();
      final message = Uint8List.fromList('Hello World'.codeUnits);
      final signature = await eccAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          eccAlgo.verifyBytes(message,
              signature: signature, publicKey: publicKey),
          completes);
    });
    test('Test invalid ecc verification - verify with a different public key',
        () async {
      final eccAlgo = EccSigningAlgo();
      final (publicKey: _, :secretKey) = await eccAlgo.generateKeyPair();
      final other = await eccAlgo.generateKeyPair();
      final message = Uint8List.fromList('Hello World'.codeUnits);
      final signature = await eccAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          eccAlgo.verifyBytes(message,
              signature: signature, publicKey: other.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });
}
