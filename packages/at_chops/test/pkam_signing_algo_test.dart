import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for pkam signing and verification', () {
    test(
        'Test pkam signing and verification using generated rsa 2048 key pair, default signing and hashing algo',
        () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      final pkamSigningAlgo =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = pkamSigningAlgo.sign(dataInBytes);
      var verifyResult = pkamSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test(
        'Test pkam signing and verification using generated rsa 4096 key pair, default signing and hashing algo',
        () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair(keySize: 4096);
      final pkamSigningAlgo =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = pkamSigningAlgo.sign(dataInBytes);
      var verifyResult = pkamSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test('Test pkam signing and verification - set sha256 hashing algo.', () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      final pkamSigningAlgo =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = pkamSigningAlgo.sign(dataInBytes);
      var verifyResult = pkamSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test(
        'Test pkam signing and verification - sign with sha256 and verify with sha512.',
        () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      final pkamSigningAlgo256 =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha256);
      final pkamSigningAlgo512 =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = pkamSigningAlgo256.sign(dataInBytes);
      var verifyResult =
          pkamSigningAlgo512.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, false);
    });

    test(
        'Test pkam signing and verification - sign with sha512 and verify with sha256.',
        () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      final pkamSigningAlgo256 =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha256);
      final pkamSigningAlgo512 =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = pkamSigningAlgo512.sign(dataInBytes);
      var verifyResult =
          pkamSigningAlgo256.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, false);
    });
    test('Test pkam signing and verification - set sha512 hashing algo', () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      final pkamSigningAlgo =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = pkamSigningAlgo.sign(dataInBytes);
      var verifyResult = pkamSigningAlgo.verify(dataInBytes, signatureInBytes);
      expect(verifyResult, true);
    });
    test(
        'Test pkam signing and verification - set md5 hashing algo - not supported',
        () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      final pkamSigningAlgo = PkamSigningAlgo(pkamKeyPair, HashingAlgoType.md5);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      expect(
          () => pkamSigningAlgo.sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtException &&
              e.toString().contains(
                  'Hashing algo HashingAlgoType.md5 is invalid/not supported'))));
    });
    test('Test pkam signing - pkam key pair not set', () {
      final pkamSigningAlgo = PkamSigningAlgo(null, HashingAlgoType.sha256);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      expect(
          () => pkamSigningAlgo.sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtException &&
              e
                  .toString()
                  .contains('pkam key pair is null. cannot sign data'))));
    });
    test('Test pkam verification - passing public key', () {
      var pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
      final pkamSigningAlgo =
          PkamSigningAlgo(pkamKeyPair, HashingAlgoType.sha512);
      final dataToSign =
          '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signatureInBytes = pkamSigningAlgo.sign(dataInBytes);
      final publicKeyString = pkamKeyPair.atPublicKey.publicKey;
      var verifyResult = pkamSigningAlgo.verify(dataInBytes, signatureInBytes,
          publicKey: publicKeyString);
      expect(verifyResult, true);
    });
  });
}
