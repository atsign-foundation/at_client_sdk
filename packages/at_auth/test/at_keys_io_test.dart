import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  String atSign = '@alice🛠';
  String keyFilePath = 'test/data/@alice🛠_key.atKeys';
  String writeFilePath = 'test/data/@bober_key.atKeys';

  group('FileAtKeysIo tests', () {
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

      expect(
        await matchesEncryptedAtKeys(atKeys, fileAtKeysIo.filePath!(atSign)),
        true,
      );
    });

    test('Test write() -> throwsA AtKeysOverwriteExpcetion)', () {
      final fileAtKeysIo = FileAtKeysIo(filePath: (_) => keyFilePath);
      AtKeys atKeys = AtKeys();
      expect(() => fileAtKeysIo.write('test', atKeys),
          throwsA(isA<AtKeysFileOverwriteException>()));
    });

    tearDownAll(() {
      final keyFile = File(writeFilePath);
      if (keyFile.existsSync()) {
        keyFile.deleteSync();
      }
    });
  });

  group('SimAtKeysIo tests', () {
    test('Test read() with valid publicKeyId', () {});
  });
}

Future<bool> matchesEncryptedAtKeys(
    AtKeys decryptedAtKeys, String filePath) async {
  final fileAtKeysIo = FileAtKeysIo(filePath: (_) => filePath);
  final encryptedAtKeysMap = jsonDecode(File(filePath).readAsStringSync());
  var decryptedAtKeysMap = await fileAtKeysIo.decryptAtKeysWithSelfEncKey(
      encryptedAtKeysMap, PkamAuthMode.keysFile);
  return decryptedAtKeys.apkamPrivateKey.toString() ==
          decryptedAtKeysMap.apkamPrivateKey.toString() &&
      decryptedAtKeys.apkamPublicKey.toString() ==
          decryptedAtKeysMap.apkamPublicKey.toString() &&
      decryptedAtKeys.apkamSymmetricKey.toString() ==
          decryptedAtKeysMap.apkamSymmetricKey.toString() &&
      decryptedAtKeys.defaultEncryptionPrivateKey.toString() ==
          decryptedAtKeysMap.defaultEncryptionPrivateKey.toString() &&
      decryptedAtKeys.defaultEncryptionPublicKey.toString() ==
          decryptedAtKeysMap.defaultEncryptionPublicKey.toString() &&
      decryptedAtKeys.defaultSelfEncryptionKey.toString() ==
          decryptedAtKeysMap.defaultSelfEncryptionKey.toString() &&
      decryptedAtKeys.enrollmentId == decryptedAtKeysMap.enrollmentId;
}
