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
    test('generateKeyPair writes an uncompressed SEC1 point and a 32-byte scalar',
        () async {
      final (:publicKey, :secretKey) = await EccSigningAlgo().generateKeyPair();
      expect(publicKey, hasLength(65));
      expect(publicKey.first, 0x04);
      expect(secretKey, hasLength(32));
    });
    test('a signature that is neither 64 nor 128 bytes is an ArgumentError',
        () async {
      final eccAlgo = EccSigningAlgo();
      final (:publicKey, secretKey: _) = await eccAlgo.generateKeyPair();
      for (final length in [0, 63, 65, 127, 129]) {
        await expectLater(
            eccAlgo.verifyBytes(Uint8List.fromList('Hello World'.codeUnits),
                signature: Uint8List(length), publicKey: publicKey),
            throwsArgumentError,
            reason: 'length $length');
      }
    });
    group('a 128-byte signature that is not hex', () {
      final message = Uint8List.fromList('Hello World'.codeUnits);
      final cases = {
        'non-hex characters': 'z' * 128,
        'a sign prefix on a byte pair': '-1${'00' * 63}',
        'multi-byte characters': '\u00e9' * 128,
      };
      for (final entry in cases.entries) {
        test('is rejected as a verification failure: ${entry.key}', () async {
          final eccAlgo = EccSigningAlgo();
          final (:publicKey, secretKey: _) = await eccAlgo.generateKeyPair();
          await expectLater(
              eccAlgo.verifyBytes(message,
                  signature: Uint8List.fromList(entry.value.codeUnits),
                  publicKey: publicKey),
              throwsA(isA<AtSigningVerificationException>()));
        });
      }
    });
  });
}
