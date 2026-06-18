import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for default signing and verification', () {
    test(
        'Test default signing and verification using generated rsa 2048 key pair, default signing and hashing algo',
        () {
      var keyPair = RsaKeyPair.generate();
      final defaultSigningAlgo =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultSigningAlgo.sign(dataInBytes);
      var verifyResult =
          defaultSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test(
        'Test default signing and verification using generated rsa 4096 key pair, default signing and hashing algo',
        () {
      var keyPair = RsaKeyPair.generate(keySize: 4096);
      final defaultSigningAlgo =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultSigningAlgo.sign(dataInBytes);
      var verifyResult =
          defaultSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test('Test default signing and verification - set sha256 hashing algo', () {
      var keyPair = RsaKeyPair.generate();
      final defaultSigningAlgo =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultSigningAlgo.sign(dataInBytes);
      var verifyResult =
          defaultSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test('Test default signing and verification - set sha512 hashing algo', () {
      var keyPair = RsaKeyPair.generate();
      final defaultSigningAlgo =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultSigningAlgo.sign(dataInBytes);
      var verifyResult =
          defaultSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test(
        'Test invalid default signing and verification - sign with sha256 and verify with sha512 hashing algo',
        () {
      var keyPair = RsaKeyPair.generate();
      final defaultsigningalgoSha256 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final defaultsigningalgoSha512 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultsigningalgoSha256.sign(dataInBytes);
      var verifyResult =
          defaultsigningalgoSha512.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, false);
    });

    test(
        'Test invalid default signing and verification - sign with sha512 and verify with sha256 hashing algo',
        () {
      var keyPair = RsaKeyPair.generate();
      final defaultsigningalgoSha256 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final defaultsigningalgoSha512 =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultsigningalgoSha512.sign(dataInBytes);
      var verifyResult =
          defaultsigningalgoSha256.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, false);
    });
    test(
        'Test default signing and verification - set md5 hashing algo - not supported',
        () {
      var keyPair = RsaKeyPair.generate();
      final defaultSigningAlgo = RsaSigningAlgo(keyPair, HashingAlgoType.md5);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      expect(
          () => defaultSigningAlgo.sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtSigningException &&
              e.toString().contains(
                  'Hashing algo HashingAlgoType.md5 is invalid/not supported'))));
    });
    test('Test default signing - key pair not set', () {
      final defaultSigningAlgo = RsaSigningAlgo(null, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      expect(
          () => defaultSigningAlgo.sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtSigningException &&
              e.toString().contains(
                  'encryption key pair not set for default signing algo'))));
    });
    test('Test default verification - passing public key', () {
      var keyPair = RsaKeyPair.generate();
      final defaultSigningAlgo =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultSigningAlgo.sign(dataInBytes);
      final publicKeyString = keyPair.atPublicKey.publicKey;
      var verifyResult = defaultSigningAlgo
          .verify(dataInBytes, signatureInBytes, publicKey: publicKeyString);
      expect(verifyResult, true);
    });

    test('Test invalid verification - passing different public key', () {
      var keyPair = RsaKeyPair.generate();
      var keyPair2 = RsaKeyPair.generate();
      final defaultSigningAlgo =
          RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = defaultSigningAlgo.sign(dataInBytes);
      final publicKeyString = keyPair2.atPublicKey.publicKey;
      var verifyResult = defaultSigningAlgo
          .verify(dataInBytes, signatureInBytes, publicKey: publicKeyString);
      expect(verifyResult, false);
    });
  });
}
