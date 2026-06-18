import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

void main() {
  AtSignLogger.root_level = 'finest';

  group('RsaSigningAlgo - sign and verify', () {
    test('sha256 sign and verify round-trip', () {
      final keyPair = RsaKeyPair.generate();
      final data = utf8.encode('testData') as Uint8List;
      final algo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);

      final signature = algo.sign(data);
      final rsaPrivateKey =
          RSAPrivateKey.fromString(keyPair.atPrivateKey.privateKey);
      expect(signature, equals(rsaPrivateKey.createSHA256Signature(data)));
      expect(algo.verify(data, signature), isTrue);
    });

    test('sha256 sign and verify - explicit algo type', () {
      final keyPair = RsaKeyPair.generate();
      final data = utf8.encode('randomText') as Uint8List;
      final algo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);

      final signature = algo.sign(data);
      final rsaPrivateKey =
          RSAPrivateKey.fromString(keyPair.atPrivateKey.privateKey);
      expect(signature, equals(rsaPrivateKey.createSHA256Signature(data)));
      expect(algo.verify(data, signature), isTrue);
    });

    test('sha512 sign and verify round-trip', () {
      final keyPair = RsaKeyPair.generate();
      final data = utf8.encode('aBcDeFg') as Uint8List;
      final algo = RsaSigningAlgo(keyPair, HashingAlgoType.sha512);

      final signature = algo.sign(data);
      final rsaPrivateKey =
          RSAPrivateKey.fromString(keyPair.atPrivateKey.privateKey);
      expect(signature, equals(rsaPrivateKey.createSHA512Signature(data)));
      expect(algo.verify(data, signature), isTrue);
    });

    test('sha256 sign, sha512 verify returns false', () {
      final keyPair = RsaKeyPair.generate();
      final data = utf8.encode('data is important') as Uint8List;
      final algoSha256 = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);
      final algoSha512 = RsaSigningAlgo(keyPair, HashingAlgoType.sha512);

      final signature = algoSha256.sign(data);
      expect(algoSha512.verify(data, signature), isFalse);
    });

    test('sha512 sign, sha256 verify returns false', () {
      final keyPair = RsaKeyPair.generate();
      final data = utf8.encode('data atad') as Uint8List;
      final algoSha512 = RsaSigningAlgo(keyPair, HashingAlgoType.sha512);
      final algoSha256 = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);

      final signature = algoSha512.sign(data);
      expect(algoSha256.verify(data, signature), isFalse);
    });

    test('verify with wrong data returns false (sha256)', () {
      final keyPair = RsaKeyPair.generate();
      final data = utf8.encode('correct data') as Uint8List;
      final wrongData = utf8.encode('wrong data') as Uint8List;
      final algo = RsaSigningAlgo(keyPair, HashingAlgoType.sha256);

      final signature = algo.sign(wrongData);
      expect(algo.verify(data, signature), isFalse);
    });

    test('verify with wrong data returns false (sha512)', () {
      final keyPair = RsaKeyPair.generate();
      final data = utf8.encode('some other random data') as Uint8List;
      final wrongData = utf8.encode('different data') as Uint8List;
      final algo = RsaSigningAlgo(keyPair, HashingAlgoType.sha512);

      final signature = algo.sign(wrongData);
      expect(algo.verify(data, signature), isFalse);
    });

    test('verify with wrong public key returns false', () {
      final keyPair1 = RsaKeyPair.generate();
      final keyPair2 = RsaKeyPair.generate();
      final data = utf8.encode('data does not matter') as Uint8List;
      final algo = RsaSigningAlgo(keyPair1, HashingAlgoType.sha256);

      final signature = algo.sign(data);
      expect(
        algo.verify(data, signature, publicKey: keyPair2.atPublicKey.publicKey),
        isFalse,
      );
    });

    test('sign without key pair throws AtSigningException', () {
      final algo = RsaSigningAlgo(null, HashingAlgoType.sha256);
      expect(
        () => algo.sign(utf8.encode('abcde')),
        throwsA(predicate((e) =>
            e is AtSigningException &&
            e.toString().contains('encryption key pair not set'))),
      );
    });
  });
}
