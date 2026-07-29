import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/src/keys/serialization/key_ids.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  final atsign = '@alice🛠'.toAtsign();
  String keyFilePath = 'test/data/@alice🛠_key.atKeys';
  late String writeFilePath;

  /// Plants the fixture in the default `.atsign/keys` layout under a throwaway
  /// home, and returns an io that resolves paths the same way `FileAtKeysIo()`
  /// does — via [getDefaultAtKeysFilePath] — just rooted somewhere disposable
  /// instead of the developer's real `$HOME`.
  FileAtKeysIo ioOverDefaultLayout() {
    final home = Directory.systemTemp.createTempSync('at_keys_io_test_home');
    addTearDown(() => home.deleteSync(recursive: true));
    final planted = File(getDefaultAtKeysFilePath(home.path, atsign));
    planted.parent.createSync(recursive: true);
    File(keyFilePath).copySync(planted.path);
    return FileAtKeysIo(
        filePath: (atsign) => getDefaultAtKeysFilePath(home.path, atsign));
  }

  group('FileAtKeysIo tests', () {
    setUp(() {
      // Written to by the write()/passphrase tests; kept out of test/data so a
      // failed run can't leave a stray keyfile in the repo.
      final tempDir =
          Directory.systemTemp.createTempSync('at_keys_io_test_write');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      writeFilePath = '${tempDir.path}/@bober_key.atKeys';
    });

    test('Test read() with valid atKeys file path', () async {
      final fileAtKeysIo = FileAtKeysIo(filePath: (_) => keyFilePath);
      final atKeys = await fileAtKeysIo.read(atsign);

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

      expect(() async => await fileAtKeysIo.read(atsign),
          throwsA(isA<AtException>()));
    });

    test('Test read() from the default .atsign/keys layout', () async {
      final fileAtKeysIo = ioOverDefaultLayout();

      final atKeys = await fileAtKeysIo.read(atsign);
      expect(atKeys.apkamPrivateKey, isNotNull);
      expect(atKeys.apkamPublicKey, isNotNull);
      expect(atKeys.apkamSymmetricKey, isNotNull);
      expect(atKeys.defaultEncryptionPrivateKey, isNotNull);
      expect(atKeys.defaultEncryptionPublicKey, isNotNull);
      expect(atKeys.defaultSelfEncryptionKey, isNotNull);
    });

    test('Test write()', () async {
      final fileAtKeysIo = FileAtKeysIo(filePath: (_) => writeFilePath);
      final atKeys = legacyAtKeys(atsign: atsign);
      await fileAtKeysIo.write(atsign, atKeys);

      await matchesEncryptedAtKeys(atKeys, fileAtKeysIo.filePath!(atsign));
    });

    test('Test write() -> throws due to overwrite', () {
      final fileAtKeysIo = FileAtKeysIo(filePath: (_) => keyFilePath);
      AtKeys atKeys = AtKeys(atsign: atsign);
      expect(() => fileAtKeysIo.write(atsign, atKeys),
          throwsA(isA<AtKeysFileOverwriteException>()));
    });

    test('Test write()/read() agree on the path for a non-canonical spelling',
        () async {
      // Regression: write() used to take a String and derive the path from it
      // verbatim, while read() normalized — so writing for '@Alice🛠' produced
      // '@Alice🛠_key.atKeys', which a read for the same identity could never
      // find. Both sides now take a normalized Atsign, so one identity is
      // always one path.
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final io = FileAtKeysIo(
          filePath: (atsign) => '${tempDir.path}/${atsign}_key.atKeys');

      await io.write('@Alice🛠'.toAtsign(),
          AtKeys(atsign: atsign, keysList: [symmetricKey('stored')]));

      expect(
        tempDir.listSync().whereType<File>().map((f) => f.path),
        [io.filePath!(atsign)],
      );
      expect((await io.read(atsign)).keysForKeyId('stored'), isNotEmpty);
    });

    test('Test write() -> should encrypt with passphrase when available',
        () async {
      final passPhrase = 'qwerty';
      final fileAtKeysIo =
          FileAtKeysIo(filePath: (_) => writeFilePath, passPhrase: passPhrase);

      final atKeys = legacyAtKeys(atsign: atsign);
      await fileAtKeysIo.write(atsign, atKeys); // writes encrypted keys

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
      await matchesEncryptedAtKeys(atKeys, fileAtKeysIo.filePath!(atsign),
          passPhrase: passPhrase);
    });

    test('Test read() -> throws with incorrect passphrase', () async {
      final passPhrase = 'abcd';
      final fileAtKeysIo =
          FileAtKeysIo(filePath: (_) => writeFilePath, passPhrase: passPhrase);

      final atKeys = legacyAtKeys(atsign: atsign);
      await fileAtKeysIo.write(atsign, atKeys); // writes encrypted keys

      fileAtKeysIo.passPhrase = 'incorrect_pass';
      await expectLater(() async => await fileAtKeysIo.read(atsign),
          throwsA(isA<AtDecryptionException>()));
    });

    test('Test flush() rewrites the existing file in place', () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final fileAtKeysIo = FileAtKeysIo(filePath: (_) => tempPath);
        final atKeys = AtKeys(
          atsign: atsign,
          keysList: [
            symmetricKey('existing', value: 'ZXhpc3Rpbmc='),
          ],
        );
        await fileAtKeysIo.write(atsign, atKeys);

        final existingText = await File(tempPath).readAsString();
        final keys = await fileAtKeysIo.read(atsign);
        keys.addKey(symmetricKey('appended', value: 'YXBwZW5kZWQ='));
        keys.addKey(symmetricKey('another', value: 'YW5vdGhlcg=='));
        await fileAtKeysIo.flush(atsign, keys);

        final files = tempDir.listSync().whereType<File>().toList();
        expect(
          files.map((file) => file.path).toSet(),
          {tempPath, '$tempPath.bak'},
        );
        expect(await File(tempPath).readAsString(), isNot(existingText));
        // The .bak preserves the pre-flush state byte-for-byte.
        expect(await File('$tempPath.bak').readAsString(), existingText);
        final reread = await fileAtKeysIo.read(atsign);
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
          atsign,
          AtKeys(atsign: atsign, keysList: [symmetricKey('fresh')]),
        );

        final readKeys = await fileAtKeysIo.read(atsign);
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
          atsign,
          AtKeys(
            atsign: atsign,
            keysList: [symmetricKey('rotated'), symmetricKey('kept')],
          ),
        );

        final keys = await fileAtKeysIo.read(atsign);
        keys.retireKey('rotated');
        await fileAtKeysIo.flush(atsign, keys);

        final reread = await fileAtKeysIo.read(atsign);
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
          atsign,
          AtKeys(
            atsign: atsign,
            keysList: [symmetricKey('existing', value: 'ZXhpc3Rpbmc=')],
          ),
        );
        final originalText = await File(tempPath).readAsString();

        // A fresh keyset that does not preserve the existing material.
        final divergent = AtKeys(
          atsign: atsign,
          keysList: [symmetricKey('unrelated')],
        );
        await expectLater(
          () async => await fileAtKeysIo.flush(atsign, divergent),
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
          atsign: atsign,
          keysList: [
            symmetricKey('sym', value: 'c2VjcmV0'),
            ...rsaKeyPair('pair',
                publicValue: 'cHVibGlj', privateValue: 'cHJpdmF0ZQ=='),
          ],
        );
        await io.write(atsign, atKeys);

        final readKeys = await io.read(atsign);
        expect(
            readKeys
                .getKey('sym', CryptographicKeyType.symmetricEncryption)
                ?.bytes
                .toString(),
            'c2VjcmV0');
        expect(
            readKeys
                .getKey('pair', CryptographicKeyType.publicEncryption)
                ?.bytes
                .toString(),
            'cHVibGlj');
        expect(
            readKeys
                .getKey('pair', CryptographicKeyType.privateDecryption)
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
          atsign: atsign,
          keysList: [
            symmetricKey('existing', value: 'ZXhpc3Rpbmc='),
          ],
        );
        await fileAtKeysIo.write(atsign, atKeys);
        final encryptedOriginal = await File(tempPath).readAsString();

        final keys = await fileAtKeysIo.read(atsign);
        keys.addKey(symmetricKey('appended', value: 'YXBwZW5kZWQ='));
        await fileAtKeysIo.flush(atsign, keys);

        final files = tempDir.listSync().whereType<File>().toList();
        expect(
          files.map((file) => file.path).toSet(),
          {tempPath, '$tempPath.bak'},
        );
        expect(await File(tempPath).readAsString(), isNot(encryptedOriginal));
        expect(await File('$tempPath.bak').readAsString(), encryptedOriginal);

        // Both keys survive a decrypt-and-read of the rewritten file.
        final readKeys = await fileAtKeysIo.read(atsign);
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
          final legacyKeys = legacyAtKeys(atsign: atsign);
          await fileAtKeysIo.write(atsign, legacyKeys);

          final keys = await fileAtKeysIo.read(atsign);
          keys.addKey(symmetricKey('appended', value: 'YXBwZW5kZWQ='));
          await fileAtKeysIo.flush(atsign, keys);

          final files = tempDir.listSync().whereType<File>().toList();
          expect(
            files.map((file) => file.path).toSet(),
            {tempPath, '$tempPath.bak'},
          );

          // The rewritten file is a typed-keys document that reads back with the
          // legacy keys intact plus the appended material.
          final readKeys = await fileAtKeysIo.read(atsign);
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
            .write(atsign, legacyAtKeys(atsign: atsign));
        await FileAtKeysIo(filePath: (_) => typedKeysPath).write(
          atsign,
          legacyAtKeys(atsign: atsign)..addKey(symmetricKey('typed')),
        );

        final Map<String, dynamic> legacyJson =
            jsonDecode(await File(legacyPath).readAsString());
        final Map<String, dynamic> typedKeysJson =
            jsonDecode(await File(typedKeysPath).readAsString());
        final plaintext = legacyAtKeys(atsign: atsign);

        expect(typedKeysJson['version'], isNotNull);
        for (final field in [
          KeyIds.apkamPublicKey,
          KeyIds.apkamPrivateKey,
          KeyIds.defaultEncryptionPublicKey,
          KeyIds.defaultEncryptionPrivateKey,
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
        final atKeys = legacyAtKeys(atsign: atsign)
          ..addKey(symmetricKey('typed'));
        await io.write(atsign, atKeys);

        final readKeys = await io.read(atsign);
        expectLegacyAtKeys(readKeys, legacyAtKeys(atsign: atsign));
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
          atsign,
          AtKeys(
            atsign: atsign,
            keysList: [symmetricKey('only-typed')],
          ),
        );

        final readKeys = await io.read(atsign);
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
        final atKeys = legacyAtKeys(atsign: atsign)
          ..defaultSelfEncryptionKey = null;

        await expectLater(
          () async => await io.write(atsign, atKeys),
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
          atsign,
          AtKeys(
            atsign: atsign,
            keysList: [symmetricKey('existing')],
          ),
        );
        final originalText = await File(tempPath).readAsString();

        final keys = await rightPassphraseIo.read(atsign);
        keys.addKey(symmetricKey('appended'));
        final wrongPassphraseIo =
            FileAtKeysIo(filePath: (_) => tempPath, passPhrase: 'wrong');
        await expectLater(
          () async => await wrongPassphraseIo.flush(atsign, keys),
          throwsA(isA<AtDecryptionException>()),
        );
        // Nothing was rewritten.
        expect(tempDir.listSync().whereType<File>().toList(), hasLength(1));
        expect(await File(tempPath).readAsString(), originalText);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test write() with a mismatched atsign -> throws, writes nothing',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final io = FileAtKeysIo(filePath: (_) => tempPath);
        final bobKeys = AtKeys(
          atsign: '@bob'.toAtsign(),
          keysList: [symmetricKey('k')],
        );

        await expectLater(
          () async => await io.write(atsign, bobKeys),
          throwsA(isA<AtKeysValidationException>()),
        );
        expect(File(tempPath).existsSync(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('Test flush() with a mismatched atsign -> throws, writes nothing',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('at_keys_io_test');
      try {
        final tempPath = '${tempDir.path}/@alice_key.atKeys';
        final io = FileAtKeysIo(filePath: (_) => tempPath);
        final bobKeys = AtKeys(
          atsign: '@bob'.toAtsign(),
          keysList: [symmetricKey('k')],
        );

        await expectLater(
          () async => await io.flush(atsign, bobKeys),
          throwsA(isA<AtKeysValidationException>()),
        );
        expect(File(tempPath).existsSync(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('SimAtKeysIo tests', () {
    test('Test read() with valid publicKeyId', () {});
  });
}

/// Asserts the file at [filePath] holds [atKeys] encrypted at rest, and reads
/// it back through a fresh [FileAtKeysIo] to prove it decrypts to the same
/// keys. The at-rest layers (the optional passphrase envelope and the
/// self-encrypted legacy portion) are internal to [FileAtKeysIo], so this goes
/// through `read` rather than peeling them apart by hand.
Future<void> matchesEncryptedAtKeys(AtKeys atKeys, String filePath,
    {String? passPhrase}) async {
  final onDisk = File(filePath).readAsStringSync();
  for (final plaintext in [
    atKeys.apkamPrivateKey,
    atKeys.apkamPublicKey,
    atKeys.defaultEncryptionPrivateKey,
    atKeys.defaultEncryptionPublicKey,
  ]) {
    expect(onDisk, isNot(contains(plaintext.toString())),
        reason: 'legacy key material must not be stored as plaintext');
  }

  final fileAtKeysIo =
      FileAtKeysIo(filePath: (_) => filePath, passPhrase: passPhrase);
  expectLegacyAtKeys(await fileAtKeysIo.read(atKeys.atsign), atKeys);
}
