import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for rsa signing and verification', () {
    test(
        'Test rsa signing and verification using generated rsa 2048 key pair, rsa signing and hashing algo',
        () {
      var keyPair = RsaKeyPair.generate();
      final rsaSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsaSigningAlgo.sign(dataInBytes);
      var verifyResult = rsaSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test(
        'Test rsa signing and verification using generated rsa 4096 key pair, rsa signing and hashing algo',
        () {
      var keyPair = RsaKeyPair.generate(keySize: 4096);
      final rsaSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsaSigningAlgo.sign(dataInBytes);
      var verifyResult = rsaSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test('Test rsa signing and verification - set sha256 hashing algo', () {
      var keyPair = RsaKeyPair.generate();
      final rsaSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsaSigningAlgo.sign(dataInBytes);
      var verifyResult = rsaSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test('Test rsa signing and verification - set sha512 hashing algo', () {
      var keyPair = RsaKeyPair.generate();
      final rsaSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsaSigningAlgo.sign(dataInBytes);
      var verifyResult = rsaSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test(
        'Test invalid rsa signing and verification - sign with sha256 and verify with sha512 hashing algo',
        () {
      var keyPair = RsaKeyPair.generate();
      final rsasigningalgoSha256 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final rsasigningalgoSha512 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsasigningalgoSha256.sign(dataInBytes);
      var verifyResult =
          rsasigningalgoSha512.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, false);
    });

    test(
        'Test invalid rsa signing and verification - sign with sha512 and verify with sha256 hashing algo',
        () {
      var keyPair = RsaKeyPair.generate();
      final rsasigningalgoSha256 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final rsasigningalgoSha512 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsasigningalgoSha512.sign(dataInBytes);
      var verifyResult =
          rsasigningalgoSha256.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, false);
    });
    test(
        'Test rsa signing and verification - set md5 hashing algo - not supported',
        () {
      var keyPair = RsaKeyPair.generate();
      final rsaSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.md5);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      expect(
          () => rsaSigningAlgo.sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtSigningException &&
              e.toString().contains(
                  'Hashing algo HashingAlgoType.md5 is invalid/not supported'))));
    });
    test('Test rsa signing - key pair not set', () {
      final rsaSigningAlgo = RsaSigningAlgo(null, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      expect(
          () => rsaSigningAlgo.sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtSigningException &&
              e.toString().contains(
                  'encryption key pair not set for rsa signing algo'))));
    });
    test('Test rsa verification - passing public key', () {
      var keyPair = RsaKeyPair.generate();
      final rsaSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsaSigningAlgo.sign(dataInBytes);
      final publicKeyString = keyPair.atPublicKey.publicKey;
      var verifyResult = rsaSigningAlgo.verify(dataInBytes, signatureInBytes,
          publicKey: publicKeyString);
      expect(verifyResult, true);
    });

    test('Test invalid verification - passing different public key', () {
      var keyPair = RsaKeyPair.generate();
      var keyPair2 = RsaKeyPair.generate();
      final rsaSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = rsaSigningAlgo.sign(dataInBytes);
      final publicKeyString = keyPair2.atPublicKey.publicKey;
      var verifyResult = rsaSigningAlgo.verify(dataInBytes, signatureInBytes,
          publicKey: publicKeyString);
      expect(verifyResult, false);
    });
  });
}
