import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

void main() {
  AtSignLogger.root_level = 'finest';
  group('A group of tests for encryption and decryption', () {
    test('Test rsa encryption/decryption string', () async {
      final atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
      final atChops = AtChopsImpl(atChopsKeys);
      final data = 'Hello World';

      final encryptionResult =
          await atChops.encryptString(data, EncryptionKeyType.rsa2048);
      expect(encryptionResult.atEncryptionMetaData, isNotNull);
      expect(encryptionResult.result, isNotEmpty);
      expect(encryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.rsa2048);
      expect(encryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'RsaEncryptionAlgo');

      final decryptionResult = await atChops.decryptString(
          encryptionResult.result, EncryptionKeyType.rsa2048);
      expect(decryptionResult.atEncryptionMetaData, isNotNull);
      expect(decryptionResult.result, isNotEmpty);
      expect(decryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.rsa2048);
      expect(decryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'RsaEncryptionAlgo');
      expect(decryptionResult.result, data);
    });

    test('Test symmetric encrypt/decrypt bytes with initialisation vector',
        () async {
      String data = 'Hello World';
      final aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      final atChopsKeys = AtChopsKeys()..selfEncryptionKey = aesKey;
      final atChops = AtChopsImpl(atChopsKeys);
      final iv = AtChopsUtil.generateRandomIV(16);

      final encryptionResult = await atChops.encryptBytes(
          // ignore: unnecessary_cast
          utf8.encode(data) as Uint8List,
          EncryptionKeyType.aes256,
          iv: iv);
      expect(encryptionResult.atEncryptionMetaData, isNotNull);
      expect(encryptionResult.result, isNotEmpty);
      expect(encryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(encryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(encryptionResult.atEncryptionMetaData.iv, iv);

      final decryptionResult = await atChops.decryptBytes(
          encryptionResult.result, EncryptionKeyType.aes256,
          iv: iv);
      expect(decryptionResult.result, isNotEmpty);
      expect(decryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(decryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(decryptionResult.atEncryptionMetaData.iv, iv);
      expect(utf8.decode(decryptionResult.result), data);
    });

    test('Test symmetric encrypt/decrypt bytes with emoji char', () async {
      String data = 'Hello World🛠';
      final aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      final atChopsKeys = AtChopsKeys()..selfEncryptionKey = aesKey;
      final atChops = AtChopsImpl(atChopsKeys);
      final iv = AtChopsUtil.generateRandomIV(16);

      final encryptionResult = await atChops.encryptBytes(
          // ignore: unnecessary_cast
          utf8.encode(data) as Uint8List,
          EncryptionKeyType.aes256,
          iv: iv);
      expect(encryptionResult.atEncryptionMetaData, isNotNull);
      expect(encryptionResult.result, isNotEmpty);
      expect(encryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(encryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(encryptionResult.atEncryptionMetaData.iv, iv);

      final decryptionResult = await atChops.decryptBytes(
          encryptionResult.result, EncryptionKeyType.aes256,
          iv: iv);
      expect(decryptionResult.result, isNotEmpty);
      expect(decryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(decryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(decryptionResult.atEncryptionMetaData.iv, iv);
      expect(utf8.decode(decryptionResult.result), data);
    });

    test('Test symmetric encrypt/decrypt bytes with special chars', () async {
      String data = 'Hello World🛠';
      final aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      final atChopsKeys = AtChopsKeys()..selfEncryptionKey = aesKey;
      final atChops = AtChopsImpl(atChopsKeys);
      final iv = AtChopsUtil.generateRandomIV(16);

      final encryptionResult = await atChops.encryptBytes(
          // ignore: unnecessary_cast
          utf8.encode(data) as Uint8List,
          EncryptionKeyType.aes256,
          iv: iv);
      expect(encryptionResult.atEncryptionMetaData, isNotNull);
      expect(encryptionResult.result, isNotEmpty);
      expect(encryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(encryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(encryptionResult.atEncryptionMetaData.iv, iv);

      final decryptionResult = await atChops.decryptBytes(
          encryptionResult.result, EncryptionKeyType.aes256,
          iv: iv);
      expect(decryptionResult.result, isNotEmpty);
      expect(decryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(decryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(decryptionResult.atEncryptionMetaData.iv, iv);
      expect(utf8.decode(decryptionResult.result), data);
    });

    test('Test symmetric encrypt/decrypt string with initialisation vector',
        () async {
      String data = 'Hello World';
      final aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      final atChopsKeys = AtChopsKeys()..selfEncryptionKey = aesKey;
      final atChops = AtChopsImpl(atChopsKeys);
      final iv = AtChopsUtil.generateRandomIV(16);

      final encryptionResult =
          await atChops.encryptString(data, EncryptionKeyType.aes256, iv: iv);
      expect(encryptionResult.atEncryptionMetaData, isNotNull);
      expect(encryptionResult.result, isNotEmpty);
      expect(encryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(encryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(encryptionResult.atEncryptionMetaData.iv, iv);

      final decryptionResult = await atChops.decryptString(
          encryptionResult.result, EncryptionKeyType.aes256,
          iv: iv);
      expect(decryptionResult.result, isNotEmpty);
      expect(decryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(decryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(decryptionResult.atEncryptionMetaData.iv, iv);
      expect(decryptionResult.result, data);
    });

    test('Test symmetric encrypt/decrypt string with special chars', () async {
      String data = 'Hello``*+%';
      final aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      final atChopsKeys = AtChopsKeys()..selfEncryptionKey = aesKey;
      final atChops = AtChopsImpl(atChopsKeys);
      final iv = AtChopsUtil.generateRandomIV(16);

      final encryptionResult =
          await atChops.encryptString(data, EncryptionKeyType.aes256, iv: iv);
      expect(encryptionResult.atEncryptionMetaData, isNotNull);
      expect(encryptionResult.result, isNotEmpty);
      expect(encryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(encryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(encryptionResult.atEncryptionMetaData.iv, iv);

      final decryptionResult = await atChops.decryptString(
          encryptionResult.result, EncryptionKeyType.aes256,
          iv: iv);
      expect(decryptionResult.result, isNotEmpty);
      expect(decryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(decryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(decryptionResult.atEncryptionMetaData.iv, iv);
      expect(decryptionResult.result, data);
    });

    test('Test symmetric encrypt/decrypt string with emoji', () async {
      String data = 'Hello World🛠';
      final aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      final atChopsKeys = AtChopsKeys()..selfEncryptionKey = aesKey;
      final atChops = AtChopsImpl(atChopsKeys);
      final iv = AtChopsUtil.generateRandomIV(16);

      final encryptionResult =
          await atChops.encryptString(data, EncryptionKeyType.aes256, iv: iv);
      expect(encryptionResult.atEncryptionMetaData, isNotNull);
      expect(encryptionResult.result, isNotEmpty);
      expect(encryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(encryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(encryptionResult.atEncryptionMetaData.iv, iv);

      final decryptionResult = await atChops.decryptString(
          encryptionResult.result, EncryptionKeyType.aes256,
          iv: iv);
      expect(decryptionResult.result, isNotEmpty);
      expect(decryptionResult.atEncryptionMetaData.encryptionKeyType,
          EncryptionKeyType.aes256);
      expect(decryptionResult.atEncryptionMetaData.atEncryptionAlgorithm,
          'AESEncryptionAlgo');
      expect(decryptionResult.atEncryptionMetaData.iv, iv);
      expect(decryptionResult.result, data);
    });

    test('validate decryption behaviour with null iv', () async {
      final aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
      final atChopsKeys = AtChopsKeys()..selfEncryptionKey = aesKey;
      final atChops = AtChopsImpl(atChopsKeys);

      var iv = AtChopsUtil.generateRandomIV(15);
      var utf8EncData = utf8.encode('abcd');
      var encryptionResult = await atChops
          .encryptBytes(utf8EncData, EncryptionKeyType.aes256, iv: iv);

      expect(
          () async => await atChops.decryptBytes(
              encryptionResult.result, EncryptionKeyType.aes256, iv: null),
          throwsA(predicate((e) =>
              e is AtDecryptionException &&
              e.toString().contains(
                  'Initialization vector required for decryption using SymmetricKey'))));
    });
  });

  group('A group of tests for data signing and verification', () {
    test(
        'Test MlDsa65PureDartAlgo algorithm-level verifyBytes accepts a valid signature and rejects a tampered one',
        () async {
      final algo = MlDsa65PureDartAlgo();
      final keyPair = await algo.generateKeyPair();
      final data = Uint8List.fromList(utf8.encode('mldsa65 dispatch test'));
      final signature =
          await algo.signBytes(data, secretKey: keyPair.secretKey);

      final verified = await algo.verifyBytes(data,
          signature: signature, publicKey: keyPair.publicKey);
      expect(verified, true);

      final tamperedData =
          Uint8List.fromList(utf8.encode('mldsa65 tampered data'));
      final tamperedVerified = await algo.verifyBytes(tamperedData,
          signature: signature, publicKey: keyPair.publicKey);
      expect(tamperedVerified, false);
    });

    test('Test sign() and verify() with default algorithms', () {
      final data = 'testData';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(encryptionKeypair, null);
      final atChops = AtChopsImpl(atChopsKeys);
      RSAPrivateKey rsaPrivateKey =
          RSAPrivateKey.fromString(encryptionKeypair.atPrivateKey.privateKey);

      AtSigningInput signingInput = AtSigningInput(data);
      signingInput.signingAlgorithm =
          DefaultSigningAlgo(encryptionKeypair, signingInput.hashingAlgoType);
      final signingResult = atChops.sign(signingInput);
      expect(signingResult.atSigningMetaData, isNotNull);
      expect(
          signingResult.result,
          base64Encode(rsaPrivateKey
              // ignore: unnecessary_cast
              .createSHA256Signature(utf8.encode(data) as Uint8List)));
      expect(signingResult.atSigningResultType, AtSigningResultType.bytes);
      expect(signingResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(signingResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha256);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(data, base64Decode(signingResult.result),
              encryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);
      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha256);
      expect(verificationResult.result, true);
    });

    test(
        'Test sign() and verify() with signingAlgo - rsa2048 and hashing algo - sha256',
        () {
      final data = 'randomText';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(encryptionKeypair, null);
      final atChops = AtChopsImpl(atChopsKeys);
      RSAPrivateKey rsaPrivateKey =
          RSAPrivateKey.fromString(encryptionKeypair.atPrivateKey.privateKey);

      AtSigningInput signingInput = AtSigningInput(data);
      signingInput.signingAlgoType = SigningAlgoType.rsa2048;
      signingInput.hashingAlgoType = HashingAlgoType.sha256;
      AtSigningAlgorithm signingAlgorithm =
          DefaultSigningAlgo(encryptionKeypair, signingInput.hashingAlgoType);
      signingInput.signingAlgorithm = signingAlgorithm;
      final signingResult = atChops.sign(signingInput);
      expect(signingResult.atSigningMetaData, isNotNull);
      expect(
          signingResult.result,
          base64Encode(rsaPrivateKey
              // ignore: unnecessary_cast
              .createSHA256Signature(utf8.encode(data) as Uint8List)));
      expect(signingResult.atSigningResultType, AtSigningResultType.bytes);
      expect(signingResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(signingResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha256);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(data, base64Decode(signingResult.result),
              encryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgoType = SigningAlgoType.rsa2048;
      verificationInput.hashingAlgoType = HashingAlgoType.sha256;
      AtSigningAlgorithm verifyAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);
      verificationInput.signingAlgorithm = verifyAlgorithm;
      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha256);
      expect(verificationResult.result, true);
    });

    test(
        'Test sign() and verify() with signingAlgo - rsa2048 and hashing algo - sha512',
        () {
      final data = 'aBcDeFg';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(encryptionKeypair, null);
      final atChops = AtChopsImpl(atChopsKeys);
      RSAPrivateKey rsaPrivateKey =
          RSAPrivateKey.fromString(encryptionKeypair.atPrivateKey.privateKey);

      AtSigningInput signingInput = AtSigningInput(data);
      signingInput.signingAlgoType = SigningAlgoType.rsa2048;
      signingInput.hashingAlgoType = HashingAlgoType.sha512;
      AtSigningAlgorithm signingAlgorithm =
          DefaultSigningAlgo(encryptionKeypair, signingInput.hashingAlgoType);
      signingInput.signingAlgorithm = signingAlgorithm;
      final signingResult = atChops.sign(signingInput);
      expect(signingResult.atSigningMetaData, isNotNull);
      expect(
          signingResult.result,
          base64Encode(rsaPrivateKey
              // ignore: unnecessary_cast
              .createSHA512Signature(utf8.encode(data) as Uint8List)));
      expect(signingResult.atSigningResultType, AtSigningResultType.bytes);
      expect(signingResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(signingResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha512);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(data, base64Decode(signingResult.result),
              encryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgoType = SigningAlgoType.rsa2048;
      verificationInput.hashingAlgoType = HashingAlgoType.sha512;
      AtSigningAlgorithm verifyAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);
      verificationInput.signingAlgorithm = verifyAlgorithm;
      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha512);
      expect(verificationResult.result, true);
    });

    test(
        'Negative test - verify() fails when verifying sha256 sign using sha512',
        () {
      final data = 'data is important';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(encryptionKeypair, null);
      final atChops = AtChopsImpl(atChopsKeys);

      AtSigningInput signingInput = AtSigningInput(data);
      signingInput.signingAlgoType = SigningAlgoType.rsa2048;
      signingInput.hashingAlgoType = HashingAlgoType.sha256;
      signingInput.signingAlgorithm =
          DefaultSigningAlgo(encryptionKeypair, signingInput.hashingAlgoType);
      final signingResult = atChops.sign(signingInput);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(data, base64Decode(signingResult.result),
              encryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgoType = SigningAlgoType.rsa2048;
      verificationInput.hashingAlgoType = HashingAlgoType.sha512;
      verificationInput.signingAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);

      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha512);
      expect(verificationResult.result, false);
    });

    test(
        'Negative test - verify() fails when verifying sha512 sign using sha256',
        () {
      final data = 'data atad';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(encryptionKeypair, null);
      final atChops = AtChopsImpl(atChopsKeys);

      AtSigningInput signingInput = AtSigningInput(data);
      signingInput.signingAlgoType = SigningAlgoType.rsa2048;
      signingInput.hashingAlgoType = HashingAlgoType.sha512;
      signingInput.signingAlgorithm =
          DefaultSigningAlgo(encryptionKeypair, signingInput.hashingAlgoType);
      final signingResult = atChops.sign(signingInput);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(data, base64Decode(signingResult.result),
              encryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgoType = SigningAlgoType.rsa2048;
      verificationInput.hashingAlgoType = HashingAlgoType.sha256;
      verificationInput.signingAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);

      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha256);
      expect(verificationResult.result, false);
    });

    test('Negative test - verify() fails with sha256 as hashing algo', () {
      final data = 'random data string';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(encryptionKeypair, null);
      final atChops = AtChopsImpl(atChopsKeys);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(
              data, 'dummysignature', encryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgoType = SigningAlgoType.rsa2048;
      verificationInput.hashingAlgoType = HashingAlgoType.sha256;
      AtSigningAlgorithm verifyAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);
      verificationInput.signingAlgorithm = verifyAlgorithm;

      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha256);
      expect(verificationResult.result, false);
    });

    test('Negative test - verify() fails with sha512 as hashing algo', () {
      final data = 'some other random data string';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final atChopsKeys = AtChopsKeys.create(encryptionKeypair, null);
      final atChops = AtChopsImpl(atChopsKeys);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(data, 'newdummysignature',
              encryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgoType = SigningAlgoType.rsa2048;
      verificationInput.hashingAlgoType = HashingAlgoType.sha512;
      AtSigningAlgorithm verifyAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);
      verificationInput.signingAlgorithm = verifyAlgorithm;

      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha512);
      expect(verificationResult.result, false);
    });

    test('Negative test - verify() fails with incorrect publicKey', () {
      final data = 'data does not matter';
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();
      final anotherEncryptionKeypair =
          AtChopsUtil.generateAtEncryptionKeyPair();
      AtEncryptionKeyPair dummyKeyPair = AtEncryptionKeyPair.create(
          encryptionKeypair.atPrivateKey.privateKey, '');
      final atChopsKeys = AtChopsKeys.create(dummyKeyPair, null);
      final atChops = AtChopsImpl(atChopsKeys);

      AtSigningInput signingInput = AtSigningInput(data);
      signingInput.signingAlgorithm =
          DefaultSigningAlgo(encryptionKeypair, signingInput.hashingAlgoType);
      final signingResult = atChops.sign(signingInput);

      AtSigningVerificationInput? verificationInput =
          AtSigningVerificationInput(data, base64Decode(signingResult.result),
              anotherEncryptionKeypair.atPublicKey.publicKey);
      verificationInput.signingAlgorithm = DefaultSigningAlgo(
          encryptionKeypair, verificationInput.hashingAlgoType);

      AtSigningResult verificationResult = atChops.verify(verificationInput);
      expect(verificationResult.atSigningMetaData, isNotNull);
      expect(verificationResult.atSigningResultType, AtSigningResultType.bool);
      expect(verificationResult.atSigningMetaData.signingAlgoType,
          SigningAlgoType.rsa2048);
      expect(verificationResult.atSigningMetaData.hashingAlgoType,
          HashingAlgoType.sha256);
      expect(verificationResult.result, false);
    });

    test('Negative test - sign() fails without encryptionKeypair', () {
      final atChopsKeys = AtChopsKeys.create(null, null);
      final atChops = AtChopsImpl(atChopsKeys);

      AtSigningInput signingInput = AtSigningInput('abcde');
      signingInput.signingAlgorithm =
          DefaultSigningAlgo(null, signingInput.hashingAlgoType);
      try {
        atChops.sign(signingInput);
      } catch (e) {
        assert(e is AtSigningException);
        expect(e.toString(),
            'Exception: encryption key pair not set for rsa signing algo');
      }
    });

    test('Negative test - sign() with incorrect DataType', () {
      final atChopsKeys = AtChopsKeys.create(null, null);
      final atChops = AtChopsImpl(atChopsKeys);
      final encryptionKeypair = AtChopsUtil.generateAtEncryptionKeyPair();

      AtSigningInput signingInput = AtSigningInput(213456777);
      signingInput.signingAlgorithm =
          DefaultSigningAlgo(encryptionKeypair, signingInput.hashingAlgoType);
      try {
        atChops.sign(signingInput);
      } catch (e) {
        assert(e is InvalidDataException);
        expect(e.toString(), 'Exception: Unrecognized type of data: 213456777');
      }
    });
  });
}
