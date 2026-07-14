import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

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

    test('Test flush() rewrites the existing file in place', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo = FileAtKeysIo(filePath: (_) => tempPath);
        final atKeys = AtKeys(
          atsign: atSign.toAtsign(),
          keysList: [
            symmetricKey('existing', value: 'ZXhpc3Rpbmc='),
          ],
        );
        await fileAtKeysIo.write(atSign, atKeys);

        final existingText = await File(tempPath).readAsString();
        final keys = await fileAtKeysIo.read(atSign);
        keys.addKey(symmetricKey('appended', value: 'YXBwZW5kZWQ='));
        keys.addKey(symmetricKey('another', value: 'YW5vdGhlcg=='));
        await fileAtKeysIo.flush(atSign.toAtsign(), keys);

        final files = tempDir.listSync().whereType<File>().toList();
        expect(files, hasLength(1));
        expect(files.single.path, tempPath);
        expect(await File(tempPath).readAsString(), isNot(existingText));
        final reread = await fileAtKeysIo.read(atSign);
        expect(reread.keysForKeyId('appended'), isNotEmpty);
        expect(reread.keysForKeyId('another'), isNotEmpty);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test flush() creates the file (and parent dirs) when absent',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/nested/dir/@alice_key.atKeys';
        final fileAtKeysIo = FileAtKeysIo(filePath: (_) => tempPath);
        await fileAtKeysIo.flush(
          atSign.toAtsign(),
          AtKeys(atsign: atSign.toAtsign(), keysList: [symmetricKey('fresh')]),
        );

        final readKeys = await fileAtKeysIo.read(atSign);
        expect(readKeys.keysForKeyId('fresh'), isNotEmpty);
        expect(
          File(tempPath).parent.listSync().whereType<File>().toList(),
          hasLength(1),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test flush() persists a retired key (status transition allowed)',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo = FileAtKeysIo(filePath: (_) => tempPath);
        await fileAtKeysIo.write(
          atSign,
          AtKeys(
            atsign: atSign.toAtsign(),
            keysList: [symmetricKey('rotated'), symmetricKey('kept')],
          ),
        );

        final keys = await fileAtKeysIo.read(atSign);
        keys.retireKey('rotated');
        await fileAtKeysIo.flush(atSign.toAtsign(), keys);

        final reread = await fileAtKeysIo.read(atSign);
        expect(
          reread.keysForKeyId('rotated').single.status,
          KeyPartStatus.retired,
        );
        expect(
          reread.keysForKeyId('kept').single.status,
          KeyPartStatus.active,
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Test flush() with a divergent AtKeys -> throws AtKeysAssuranceException '
        'and writes nothing', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo = FileAtKeysIo(filePath: (_) => tempPath);
        await fileAtKeysIo.write(
          atSign,
          AtKeys(
            atsign: atSign.toAtsign(),
            keysList: [symmetricKey('existing', value: 'ZXhpc3Rpbmc=')],
          ),
        );
        final originalText = await File(tempPath).readAsString();

        // A fresh keyset that does not preserve the existing material.
        final divergent = AtKeys(
          atsign: atSign.toAtsign(),
          keysList: [symmetricKey('unrelated')],
        );
        await expectLater(
          () async => await fileAtKeysIo.flush(atSign.toAtsign(), divergent),
          throwsA(isA<AtKeysAssuranceException>()),
        );

        // Nothing was rewritten.
        expect(tempDir.listSync().whereType<File>().toList(), hasLength(1));
        expect(await File(tempPath).readAsString(), originalText);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test write()/read() round-trips typed keys', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final io = FileAtKeysIo(filePath: (_) => tempPath);
        final atKeys = AtKeys(
          atsign: atSign.toAtsign(),
          keysList: [
            symmetricKey('sym', value: 'c2VjcmV0'),
            ...rsaKeyPair('pair',
                publicValue: 'cHVibGlj', privateValue: 'cHJpdmF0ZQ=='),
          ],
        );
        await io.write(atSign, atKeys);

        final readKeys = await io.read(atSign);
        expect(
            readKeys
                .getKey('sym', CryptographicKeyType.symmetricDataEncryption)
                ?.bytes
                .toString(),
            'c2VjcmV0');
        expect(
            readKeys
                .getKey('pair', CryptographicKeyType.classicalPublicEncryption)
                ?.bytes
                .toString(),
            'cHVibGlj');
        expect(
            readKeys
                .getKey('pair', CryptographicKeyType.classicalPrivateDecryption)
                ?.bytes
                .toString(),
            'cHJpdmF0ZQ==');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test flush() round-trips through a passphrase-protected file',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo =
            FileAtKeysIo(filePath: (_) => tempPath, passPhrase: 'qwerty');
        final atKeys = AtKeys(
          atsign: atSign.toAtsign(),
          keysList: [
            symmetricKey('existing', value: 'ZXhpc3Rpbmc='),
          ],
        );
        await fileAtKeysIo.write(atSign, atKeys);
        final encryptedOriginal = await File(tempPath).readAsString();

        final keys = await fileAtKeysIo.read(atSign);
        keys.addKey(symmetricKey('appended', value: 'YXBwZW5kZWQ='));
        await fileAtKeysIo.flush(atSign.toAtsign(), keys);

        final files = tempDir.listSync().whereType<File>().toList();
        expect(files, hasLength(1));
        expect(files.single.path, tempPath);
        expect(await File(tempPath).readAsString(), isNot(encryptedOriginal));

        // Both keys survive a decrypt-and-read of the rewritten file.
        final readKeys = await fileAtKeysIo.read(atSign);
        expect(readKeys.keysForKeyId('existing'), isNotEmpty);
        expect(readKeys.keysForKeyId('appended'), isNotEmpty);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    for (final passPhrase in [null, 'qwerty']) {
      test(
          'Test flush() upgrades a legacy file to a typed-keys document'
          '${passPhrase == null ? '' : ' with passphrase'}', () async {
        final tempDir =
            await Directory.systemTemp.createTemp('at_keys_io_test');
        try {
          final tempPath = '${tempDir.path}/@alice_key.atKeys';
          final fileAtKeysIo =
              FileAtKeysIo(filePath: (_) => tempPath, passPhrase: passPhrase);
          final legacyKeys = legacyAtKeys();
          await fileAtKeysIo.write(atSign, legacyKeys);

          final keys = await fileAtKeysIo.read(atSign);
          keys.addKey(symmetricKey('appended', value: 'YXBwZW5kZWQ='));
          await fileAtKeysIo.flush(atSign.toAtsign(), keys);

          final files = tempDir.listSync().whereType<File>().toList();
          expect(files, hasLength(1));
          expect(files.single.path, tempPath);

          // The rewritten file is a typed-keys document that reads back with the
          // legacy keys intact plus the appended material.
          final readKeys = await fileAtKeysIo.read(atSign);
          expectLegacyAtKeys(readKeys, legacyKeys);
          expect(readKeys.keysForKeyId('appended'), isNotEmpty);
        } finally {
          await tempDir.delete(recursive: true);
        }
      });
    }

    test(
        'Test write() self-encrypts the legacy portion of a typed-keys '
        'document, byte-identical to a legacy-only file', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final legacyPath = '${tempDir.path}/@legacy_key.atKeys';
        final typedKeysPath = '${tempDir.path}/@typed_key.atKeys';
        await FileAtKeysIo(filePath: (_) => legacyPath)
            .write(atSign, legacyAtKeys());
        await FileAtKeysIo(filePath: (_) => typedKeysPath).write(
          atSign,
          legacyAtKeys(atsign: atSign.toAtsign())
            ..addKey(symmetricKey('typed')),
        );

        final Map<String, dynamic> legacyJson =
            jsonDecode(await File(legacyPath).readAsString());
        final Map<String, dynamic> typedKeysJson =
            jsonDecode(await File(typedKeysPath).readAsString());
        final plaintext = legacyAtKeys();

        expect(typedKeysJson['version'], isNotNull);
        for (final field in [
          auth_constants.apkamPublicKey,
          auth_constants.apkamPrivateKey,
          auth_constants.defaultEncryptionPublicKey,
          auth_constants.defaultEncryptionPrivateKey,
        ]) {
          expect(typedKeysJson[field], legacyJson[field],
              reason: '$field must match the legacy-only encoding');
          expect(typedKeysJson[field], isNot(plaintext.toJson()[field]),
              reason: '$field must not be stored as plaintext');
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Test read() returns plaintext legacy fields from a typed-keys document',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final io = FileAtKeysIo(filePath: (_) => tempPath);
        final atKeys = legacyAtKeys(atsign: atSign.toAtsign())
          ..addKey(symmetricKey('typed'));
        await io.write(atSign, atKeys);

        final readKeys = await io.read(atSign);
        expectLegacyAtKeys(readKeys, legacyAtKeys());
        expect(readKeys.keysForKeyId('typed'), isNotEmpty);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Test write()/read() works for typed materials only '
        '(no selfEncryptionKey needed)', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final io = FileAtKeysIo(filePath: (_) => tempPath);
        await io.write(
          atSign,
          AtKeys(
            atsign: atSign.toAtsign(),
            keysList: [symmetricKey('only-typed')],
          ),
        );

        final readKeys = await io.read(atSign);
        expect(readKeys.keysForKeyId('only-typed'), isNotEmpty);
        expect(readKeys.defaultSelfEncryptionKey, isNull);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'Test write() with legacy fields but no selfEncryptionKey '
        '-> throws before touching the file', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final io = FileAtKeysIo(filePath: (_) => tempPath);
        final atKeys = legacyAtKeys()..defaultSelfEncryptionKey = null;

        await expectLater(
          () async => await io.write(atSign, atKeys),
          throwsA(isA<AtException>()),
        );
        expect(File(tempPath).existsSync(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test flush() with an incorrect passphrase -> throws', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final rightPassphraseIo =
            FileAtKeysIo(filePath: (_) => tempPath, passPhrase: 'right');
        await rightPassphraseIo.write(
          atSign,
          AtKeys(
            atsign: atSign.toAtsign(),
            keysList: [symmetricKey('existing')],
          ),
        );
        final originalText = await File(tempPath).readAsString();

        final keys = await rightPassphraseIo.read(atSign);
        keys.addKey(symmetricKey('appended'));
        final wrongPassphraseIo =
            FileAtKeysIo(filePath: (_) => tempPath, passPhrase: 'wrong');
        await expectLater(
          () async => await wrongPassphraseIo.flush(atSign.toAtsign(), keys),
          throwsA(isA<AtDecryptionException>()),
        );
        // Nothing was rewritten.
        expect(tempDir.listSync().whereType<File>().toList(), hasLength(1));
        expect(await File(tempPath).readAsString(), originalText);
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
