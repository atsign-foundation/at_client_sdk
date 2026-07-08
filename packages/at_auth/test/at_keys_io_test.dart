import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  String atSign = '@alice🛠';
  String keyFilePath = 'test/data/@alice🛠_key.atKeys';
  String writeFilePath = 'test/data/@bober_key.atKeys';
  late String homeDirKeys;

  group('FileAtKeysIo tests', () {
    setUp(() {
      var homeDir = getHomeDirectory();
      homeDirKeys = '$homeDir/.atsign/keys/@alice🛠_key.atKeys';
      Directory keysDir = Directory(homeDirKeys).parent;
      if (!keysDir.existsSync()) {
        keysDir.createSync(recursive: true);
      }
      File(keyFilePath).copySync(homeDirKeys);
    });

    test('Test read() with valid atKeys file path', () async {
      final fileAtKeysIo = FileAtKeysIo(filePath: (_) => keyFilePath);
      final atKeys = await fileAtKeysIo.read(atSign);

      expect(atKeys.apkamPrivateKey, isNotNull);
      expect(atKeys.apkamPublicKey, isNotNull);
      expect(atKeys.apkamSymmetricKey, isNotNull);
      expect(atKeys.defaultEncryptionPrivateKey, isNotNull);
      expect(atKeys.defaultEncryptionPublicKey, isNotNull);
      expect(atKeys.defaultSelfEncryptionKey, isNotNull);
    });

    test('Test read() with invalid atKeys file path', () async {
      final fileAtKeysIo =
          FileAtKeysIo(filePath: (_) => 'test/data/hello/@alice🛠_key.atKeys');

      expect(() async => await fileAtKeysIo.read(atSign),
          throwsA(isA<AtException>()));
    });

    test('Test read() without atKeys file path', () async {
      final fileAtKeysIo = FileAtKeysIo();

      final atKeys = await fileAtKeysIo.read(atSign);
      expect(atKeys.apkamPrivateKey, isNotNull);
      expect(atKeys.apkamPublicKey, isNotNull);
      expect(atKeys.apkamSymmetricKey, isNotNull);
      expect(atKeys.defaultEncryptionPrivateKey, isNotNull);
      expect(atKeys.defaultEncryptionPublicKey, isNotNull);
      expect(atKeys.defaultSelfEncryptionKey, isNotNull);
    });

    test('Test write()', () async {
      final fileAtKeysIo = FileAtKeysIo(filePath: (_) => writeFilePath);
      final atKeys = AtKeys()
        ..apkamPublicKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
        ..apkamPrivateKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPrivateKey')))
        ..defaultEncryptionPublicKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPublicKey')))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
        ..defaultSelfEncryptionKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultSelfEncryptionKey')))
        ..apkamSymmetricKey =
            AtBytes.fromString(base64Encode(utf8.encode('apkamSymmetricKey')))
        ..enrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
      await fileAtKeysIo.write(atSign, atKeys);

      await matchesEncryptedAtKeys(atKeys, fileAtKeysIo.filePath!(atSign));
    });

    test('Test write() -> throws due to overwrite', () {
      final fileAtKeysIo = FileAtKeysIo(filePath: (_) => keyFilePath);
      AtKeys atKeys = AtKeys();
      expect(() => fileAtKeysIo.write('test', atKeys),
          throwsA(isA<AtKeysFileOverwriteException>()));
    });

    test('Test write() -> should encrypt with passphrase when available',
        () async {
      final passPhrase = 'qwerty';
      final fileAtKeysIo =
          FileAtKeysIo(filePath: (_) => writeFilePath, passPhrase: passPhrase);

      final atKeys = AtKeys()
        ..apkamPublicKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
        ..apkamPrivateKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPrivateKey')))
        ..defaultEncryptionPublicKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPublicKey')))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
        ..defaultSelfEncryptionKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultSelfEncryptionKey')))
        ..apkamSymmetricKey =
            AtBytes.fromString(base64Encode(utf8.encode('apkamSymmetricKey')))
        ..enrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
      await fileAtKeysIo.write(atSign, atKeys); // writes encrypted keys

      // read the generated file and validate fields
      File encryptedAtKeysFile = File(writeFilePath);
      Map encryptedFileContent =
          jsonDecode(encryptedAtKeysFile.readAsStringSync());
      expect(encryptedFileContent['content'], isNotNull);
      expect(encryptedFileContent['iv'], isNotNull);
      expect(encryptedFileContent['hashingAlgoType'], 'argon2id');

      // assert that when fileAtKeysIo decrypts and reads the passphrase
      // encrypted file the decrypted keys are the same as the original keys
      // Note: the method call below tests the encrypted keys read path too
      await matchesEncryptedAtKeys(atKeys, fileAtKeysIo.filePath!(atSign),
          passPhrase: passPhrase);
    });

    test('Test read() -> throws with incorrect passphrase', () async {
      final passPhrase = 'abcd';
      final fileAtKeysIo =
          FileAtKeysIo(filePath: (_) => writeFilePath, passPhrase: passPhrase);

      final atKeys = AtKeys()
        ..apkamPublicKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
        ..apkamPrivateKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPrivateKey')))
        ..defaultEncryptionPublicKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPublicKey')))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
        ..defaultSelfEncryptionKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultSelfEncryptionKey')))
        ..apkamSymmetricKey =
            AtBytes.fromString(base64Encode(utf8.encode('apkamSymmetricKey')))
        ..enrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
      await fileAtKeysIo.write(atSign, atKeys); // writes encrypted keys

      fileAtKeysIo.passPhrase = 'incorrect_pass';
      await expectLater(() async => await fileAtKeysIo.read(atSign),
          throwsA(isA<AtDecryptionException>()));
    });

    tearDown(() {
      final keyFile = File(writeFilePath);
      if (keyFile.existsSync()) {
        keyFile.deleteSync();
      }
      File(homeDirKeys).deleteSync();
    });
  });

  group('SimAtKeysIo tests', () {
    test('Test read() with valid publicKeyId', () {});
  });
}

Future<void> matchesEncryptedAtKeys(AtKeys atKeys, String filePath,
    {String? passPhrase}) async {
  final fileAtKeysIo =
      FileAtKeysIo(filePath: (_) => filePath, passPhrase: passPhrase);

  Map<String, dynamic> atKeysFromFile =
      jsonDecode(File(filePath).readAsStringSync());

  // decrypt if passPhrase available
  if (passPhrase != null) {
    atKeysFromFile =
        await fileAtKeysIo.decodeAtKeys(atKeysFromFile, passPhrase: passPhrase);
  }

  // decrypt the atKeys read from file with self encryption key
  AtKeys decryptedAtKeys = await fileAtKeysIo.decryptAtKeysWithSelfEncKey(
      atKeysFromFile, PkamAuthMode.keysFile);

  expect(decryptedAtKeys.apkamPrivateKey.toString(),
      atKeys.apkamPrivateKey.toString());
  expect(decryptedAtKeys.apkamPublicKey.toString(),
      atKeys.apkamPublicKey.toString());
  expect(decryptedAtKeys.apkamSymmetricKey.toString(),
      atKeys.apkamSymmetricKey.toString());
  expect(decryptedAtKeys.defaultEncryptionPrivateKey.toString(),
      atKeys.defaultEncryptionPrivateKey.toString());
  expect(decryptedAtKeys.defaultEncryptionPublicKey.toString(),
      atKeys.defaultEncryptionPublicKey.toString());
  expect(decryptedAtKeys.defaultSelfEncryptionKey.toString(),
      atKeys.defaultSelfEncryptionKey.toString());
  expect(decryptedAtKeys.enrollmentId, atKeys.enrollmentId);
}
