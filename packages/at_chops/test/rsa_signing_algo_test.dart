import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  final message = Uint8List.fromList(
      '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f'
          .codeUnits);

  group('A group of tests for rsa signing and verification', () {
    test('Test rsa signing and verification using generated rsa 2048 key pair',
        () async {
      final rsaSigningAlgo = RsaSigningAlgo();
      final (:publicKey, :secretKey) = await rsaSigningAlgo.generateKeyPair();
      final signature =
          await rsaSigningAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          rsaSigningAlgo.verifyBytes(message,
              signature: signature, publicKey: publicKey),
          completes);
    });
    test('Test rsa signing and verification using generated rsa 4096 key pair',
        () async {
      final rsaSigningAlgo = RsaSigningAlgo(keySize: 4096);
      final (:publicKey, :secretKey) = await rsaSigningAlgo.generateKeyPair();
      final signature =
          await rsaSigningAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          rsaSigningAlgo.verifyBytes(message,
              signature: signature, publicKey: publicKey),
          completes);
    });
    test('Test rsa signing and verification - sha512 hashing algo', () async {
      final rsaSigningAlgo =
          RsaSigningAlgo(hashingAlgoType: HashingAlgoType.sha512);
      final (:publicKey, :secretKey) = await rsaSigningAlgo.generateKeyPair();
      final signature =
          await rsaSigningAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          rsaSigningAlgo.verifyBytes(message,
              signature: signature, publicKey: publicKey),
          completes);
    });
    test(
        'Test invalid rsa verification - sign with sha256 and verify with sha512',
        () async {
      final sha256Algo =
          RsaSigningAlgo(hashingAlgoType: HashingAlgoType.sha256);
      final sha512Algo =
          RsaSigningAlgo(hashingAlgoType: HashingAlgoType.sha512);
      final (:publicKey, :secretKey) = await sha256Algo.generateKeyPair();
      final signature =
          await sha256Algo.signBytes(message, secretKey: secretKey);
      await expectLater(
          sha512Algo.verifyBytes(message,
              signature: signature, publicKey: publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
    test('Test rsa signing - md5 hashing algo not supported', () async {
      final rsaSigningAlgo =
          RsaSigningAlgo(hashingAlgoType: HashingAlgoType.md5);
      final (:secretKey, :publicKey) = await rsaSigningAlgo.generateKeyPair();
      expect(
          () => rsaSigningAlgo.signBytes(message, secretKey: secretKey),
          throwsA(predicate((e) =>
              e is AtSigningException &&
              e.toString().contains(
                  'Hashing algo HashingAlgoType.md5 is invalid/not supported'))));
    });
    test('Test rsa verification - md5 hashing algo not supported', () async {
      final rsaSigningAlgo =
          RsaSigningAlgo(hashingAlgoType: HashingAlgoType.md5);
      final (:secretKey, :publicKey) = await rsaSigningAlgo.generateKeyPair();
      expect(
          () => rsaSigningAlgo.verifyBytes(message,
              signature: secretKey, publicKey: publicKey),
          throwsA(predicate((e) =>
              e is AtSigningVerificationException &&
              e
                  .toString()
                  .contains('Invalid hashing algo HashingAlgoType.md5'))));
    });
    test('Test invalid rsa verification - verify with a different public key',
        () async {
      final rsaSigningAlgo = RsaSigningAlgo();
      final (publicKey: _, :secretKey) = await rsaSigningAlgo.generateKeyPair();
      final other = await rsaSigningAlgo.generateKeyPair();
      final signature =
          await rsaSigningAlgo.signBytes(message, secretKey: secretKey);
      await expectLater(
          rsaSigningAlgo.verifyBytes(message,
              signature: signature, publicKey: other.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });
}
