import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  String atSign = '@alice🛠';
  String keyFilePath = 'test/data/@alice🛠_key.atKeys';

  group('FileAtKeysIo tests', () {
    test('Test read() with valid atKeys file path', () async {
      final fileAtKeysIo = FileAtKeysIo(filePath: keyFilePath);
      final atKeys = await fileAtKeysIo.read(atSign);

      expect(atKeys.apkamPrivateKey, isNotNull);
      expect(atKeys.apkamPublicKey, isNotNull);
      expect(atKeys.apkamSymmetricKey, isNotNull);
      expect(atKeys.defaultEncryptionPrivateKey, isNotNull);
      expect(atKeys.defaultEncryptionPublicKey, isNotNull);
      expect(atKeys.defaultSelfEncryptionKey, isNotNull);
    });

    test('Test read() with invalid atKeys file path', () async {
      final fileAtKeysIo = FileAtKeysIo(filePath: 'test/data/hello/@alice🛠_key.atKeys');

      expect(() async => await fileAtKeysIo.read(atSign), throwsA(isA<AtException>()));
    });

    test('Test read() without atKeys file path', () async {
      final fileAtKeysIo = FileAtKeysIo();
      expect(() async => await fileAtKeysIo.read(atSign), throwsA(isA<AtException>()));
    });

    test('Test write()', () async {
      final fileAtKeysIo = FileAtKeysIo(filePath: keyFilePath);
      final atKeys = AtKeys()
        ..apkamPublicKey = AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
        ..apkamPrivateKey = AtBytes.fromString(base64Encode(utf8.encode('testApkamPrivateKey')))
        ..defaultEncryptionPublicKey = AtBytes.fromString(base64Encode(utf8.encode('defaultEncryptionPublicKey')))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
        ..defaultSelfEncryptionKey = AtBytes.fromString(base64Encode(utf8.encode('defaultSelfEncryptionKey')))
        ..enrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
      await fileAtKeysIo.write(atSign, atKeys);

      expect(matchesEncryptedAtKeys(atKeys, fileAtKeysIo.filePath!), true);
    });
  });

  group('SimAtKeysIo tests', () {
    test('Test read() with valid publicKeyId', () {
      
    });
  });
}

bool matchesEncryptedAtKeys(AtKeys decryptedAtKeys, String filePath) {
  final fileAtKeysIo = FileAtKeysIo(filePath: filePath);
  final encryptedAtKeysMap = jsonDecode(File(filePath).readAsStringSync());
  var decryptedAtKeysMap = fileAtKeysIo.decryptAtKeysWithSelfEncKey(encryptedAtKeysMap, PkamAuthMode.keysFile);
  return decryptedAtKeys.apkamPrivateKey.toString() == decryptedAtKeysMap.apkamPrivateKey.toString() &&
      decryptedAtKeys.apkamPublicKey.toString() == decryptedAtKeysMap.apkamPublicKey.toString() &&
      decryptedAtKeys.apkamSymmetricKey.toString() == decryptedAtKeysMap.apkamSymmetricKey.toString() &&
      decryptedAtKeys.defaultEncryptionPrivateKey.toString() ==
          decryptedAtKeysMap.defaultEncryptionPrivateKey.toString() &&
      decryptedAtKeys.defaultEncryptionPublicKey.toString() ==
          decryptedAtKeysMap.defaultEncryptionPublicKey.toString() &&
      decryptedAtKeys.defaultSelfEncryptionKey.toString() == decryptedAtKeysMap.defaultSelfEncryptionKey.toString() &&
      decryptedAtKeys.enrollmentId == decryptedAtKeysMap.enrollmentId;
}
