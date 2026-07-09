import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/types.dart';
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

    test('Test append() archives the existing file before overwriting',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo = FileAtKeysIo(filePath: (_) => tempPath);
        final atKeys = AtKeys(
          atsign: atSign.toAtsign(),
          keysList: [
            AtSymmetricKey(
              id: 'existing',
              algorithm: 'AES-256',
              bytes: AtBytes.fromString('ZXhpc3Rpbmc='),
            ),
          ],
        );
        await fileAtKeysIo.write(atSign, atKeys);

        final existingText = await File(tempPath).readAsString();
        await fileAtKeysIo.append(
          atSign.toAtsign(),
          AtSymmetricKey(
            id: 'appended',
            algorithm: 'AES-256',
            bytes: AtBytes.fromString('YXBwZW5kZWQ='),
          ),
        );

        final archives = tempDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.startsWith('$tempPath.'))
            .toList();
        expect(archives, hasLength(1));
        expect(await archives.single.readAsString(), existingText);
        expect(await File(tempPath).readAsString(), isNot(existingText));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test write()/read() round-trips v1 typed keys', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final io = FileAtKeysIo(filePath: (_) => tempPath);
        final atKeys = AtKeys(
          atsign: atSign.toAtsign(),
          keysList: [
            AtSymmetricKey(
              id: 'sym',
              algorithm: 'AES-256',
              bytes: AtBytes.fromString('c2VjcmV0'),
            ),
            AtPublicKey(
              pairId: 'pair',
              algorithm: 'RSA',
              bytes: AtBytes.fromString('cHVibGlj'),
            ),
            AtPrivateKey(
              pairId: 'pair',
              algorithm: 'RSA',
              bytes: AtBytes.fromString('cHJpdmF0ZQ=='),
            ),
          ],
        );
        await io.write(atSign, atKeys);

        final readKeys = await io.read(atSign);
        expect(readKeys.getKey<AtSymmetricKey>('sym')?.bytes.toString(),
            'c2VjcmV0');
        expect(
            readKeys.getKey<AtPublicKey>('pair')?.bytes.toString(), 'cHVibGlj');
        expect(readKeys.getKey<AtPrivateKey>('pair')?.bytes.toString(),
            'cHJpdmF0ZQ==');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test append() round-trips through a passphrase-protected file',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo =
            FileAtKeysIo(filePath: (_) => tempPath, passPhrase: 'qwerty');
        final atKeys = AtKeys(
          atsign: atSign.toAtsign(),
          keysList: [
            AtSymmetricKey(
              id: 'existing',
              algorithm: 'AES-256',
              bytes: AtBytes.fromString('ZXhpc3Rpbmc='),
            ),
          ],
        );
        await fileAtKeysIo.write(atSign, atKeys);
        final encryptedOriginal = await File(tempPath).readAsString();

        await fileAtKeysIo.append(
          atSign.toAtsign(),
          AtSymmetricKey(
            id: 'appended',
            algorithm: 'AES-256',
            bytes: AtBytes.fromString('YXBwZW5kZWQ='),
          ),
        );

        // The archive keeps the original bytes verbatim (still encrypted).
        final archives = tempDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.startsWith('$tempPath.'))
            .toList();
        expect(archives, hasLength(1));
        expect(await archives.single.readAsString(), encryptedOriginal);

        // Both keys survive a decrypt-and-read of the rewritten file.
        final readKeys = await fileAtKeysIo.read(atSign);
        expect(readKeys.getKey<AtSymmetricKey>('existing'), isNotNull);
        expect(readKeys.getKey<AtSymmetricKey>('appended'), isNotNull);
      } finally {
        await tempDir.delete(recursive: true);
      }
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
