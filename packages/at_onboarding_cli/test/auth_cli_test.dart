import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli_args.dart';
import 'package:test/test.dart';
import 'at_onboarding_cli_test.dart';

void main() {
  final baseDirPath = 'test/keys';

  group('A group of tests to verify write permission of apkam file path', () {
    final dirPath = '$baseDirPath/@alice-apkam-keys.atKeys';

    test(
        'A test to verify isWritable returns false if directory has read-only permissions',
        () async {
      final directory = Directory(dirPath);
      // Create the directory first to ensure it exists before calling isWritable.
      await directory.create(recursive: true);
      // Set permission to read only.
      await Process.run('chmod', ['444', baseDirPath]);
      expect(canCreateFile(File(dirPath)), false);
    });

    test(
        'A test verify isWritable returns true if directory does not have a file already',
        () {
      expect(canCreateFile(File(dirPath)), true);
    });
  });

  group('decrypt command tests', () {
    late Directory tempDir;
    late String testAtSign;
    late String passPhrase;
    late AtKeys testAtKeys;
    late File encryptedAtKeysFile;
    late File decryptedTargetFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('decrypt_test_');
      testAtSign = '@alice_decrypt_test';
      passPhrase = 'test_passphrase_123';

      // Generate test AtKeys
      AtChopsKeys atChopsKeys = getRandomAtChopsKeys();
      testAtKeys = _getAtAuthKeysFromAtChopsKeys(atChopsKeys);

      encryptedAtKeysFile =
          File('${tempDir.path}/${testAtSign}_encrypted.atKeys');
      decryptedTargetFile =
          File('${tempDir.path}/${testAtSign}_decrypted.atKeys');

      // Write encrypted atKeys using FileAtKeysIo with passPhrase
      FileAtKeysIo fileAtKeysIo = FileAtKeysIo(
          filePath: (_) => encryptedAtKeysFile.path, passPhrase: passPhrase);
      await fileAtKeysIo.write(testAtSign, testAtKeys);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Decrypt command successfully decrypts passphrase-protected atKeys',
        () async {
      final decryptParser = AuthCliArgs().createDecryptCommandParser();

      // Build arguments
      final args = [
        '--${AuthCliArgs.argNameAtSign}',
        testAtSign,
        '--${AuthCliArgs.argNameAtKeys}',
        encryptedAtKeysFile.path,
        '--${AuthCliArgs.argNamePassPhrase}',
        passPhrase,
        '--${AuthCliArgs.argNameTargetAtKeys}',
        decryptedTargetFile.path,
      ];

      // decrypt
      final argResults = decryptParser.parse(args);
      await passPhraseDecryptAtKeys(argResults);

      expect(decryptedTargetFile.existsSync(), isTrue);

      // Read the decrypted keys
      FileAtKeysIo decryptedFileIo =
          FileAtKeysIo(filePath: (_) => decryptedTargetFile.path);
      AtKeys decryptedKeys = await decryptedFileIo.read(testAtSign);

      // Verify all keys match
      expect(decryptedKeys.apkamPublicKey.toString(),
          equals(testAtKeys.apkamPublicKey.toString()));
      expect(decryptedKeys.apkamPrivateKey.toString(),
          equals(testAtKeys.apkamPrivateKey.toString()));
      expect(decryptedKeys.defaultEncryptionPublicKey.toString(),
          equals(testAtKeys.defaultEncryptionPublicKey.toString()));
      expect(decryptedKeys.defaultEncryptionPrivateKey.toString(),
          equals(testAtKeys.defaultEncryptionPrivateKey.toString()));
      expect(decryptedKeys.defaultSelfEncryptionKey.toString(),
          equals(testAtKeys.defaultSelfEncryptionKey.toString()));
      expect(decryptedKeys.apkamSymmetricKey.toString(),
          equals(testAtKeys.apkamSymmetricKey.toString()));
    });

    test('Decrypt command appends .atKeys extension if not present', () async {
      // Target file without .atKeys
      String targetKeysWithoutExtension =
          '${tempDir.path}/${testAtSign}_output';
      File expectedFile = File('$targetKeysWithoutExtension.atKeys');

      final decryptParser = AuthCliArgs().createDecryptCommandParser();

      final args = [
        '--${AuthCliArgs.argNameAtSign}',
        testAtSign,
        '--${AuthCliArgs.argNameAtKeys}',
        encryptedAtKeysFile.path,
        '--${AuthCliArgs.argNamePassPhrase}',
        passPhrase,
        '--${AuthCliArgs.argNameTargetAtKeys}',
        targetKeysWithoutExtension,
      ];

      // decrypt
      final argResults = decryptParser.parse(args);
      await passPhraseDecryptAtKeys(argResults);

      // assert that the file has been created with a .atKeys extension
      expect(expectedFile.existsSync(), isTrue);

      await expectedFile.delete();
    });

    test('Decrypt command with incorrect passphrase throws an error', () async {
      final decryptParser = AuthCliArgs().createDecryptCommandParser();
      final File atKeysFile =
          File('${tempDir.path}/${testAtSign}_wrong_passphrase.atKeys');

      final args = [
        '--${AuthCliArgs.argNameAtSign}',
        testAtSign,
        '--${AuthCliArgs.argNameAtKeys}',
        encryptedAtKeysFile.path,
        '--${AuthCliArgs.argNamePassPhrase}',
        'wrong_passphrase',
        '--${AuthCliArgs.argNameTargetAtKeys}',
        atKeysFile.path,
      ];

      // decrypt
      final argResults = decryptParser.parse(args);
      await expectLater(
        () => passPhraseDecryptAtKeys(argResults),
        throwsA(isA<AtDecryptionException>()),
      );
    });

    test('Decrypt command fails when source file does not exist', () async {
      final decryptParser = AuthCliArgs().createDecryptCommandParser();

      final args = [
        '--${AuthCliArgs.argNameAtSign}',
        testAtSign,
        '--${AuthCliArgs.argNameAtKeys}',
        '${tempDir.path}/nonexistent.atKeys',
        '--${AuthCliArgs.argNamePassPhrase}',
        passPhrase,
        '--${AuthCliArgs.argNameTargetAtKeys}',
        decryptedTargetFile.path,
      ];

      final argResults = decryptParser.parse(args);

      expect(() async => await passPhraseDecryptAtKeys(argResults),
          throwsA(isA<ArgumentError>()));
    });

    test('Decrypt command fails when target file already exists', () async {
      final decryptParser = AuthCliArgs().createDecryptCommandParser();

      final args = [
        '--${AuthCliArgs.argNameAtSign}',
        testAtSign,
        '--${AuthCliArgs.argNameAtKeys}',
        encryptedAtKeysFile.path,
        '--${AuthCliArgs.argNamePassPhrase}',
        passPhrase,
        '--${AuthCliArgs.argNameTargetAtKeys}',
        // using the existing encrypted keys file path as the target path
        encryptedAtKeysFile.path,
      ];

      // decrypt
      final argResults = decryptParser.parse(args);
      await expectLater(() async => await passPhraseDecryptAtKeys(argResults),
          throwsA(isA<AtKeysFileOverwriteException>()));
    });
  });

  tearDown(() async {
    final absPath = '${Directory.current.path}/$baseDirPath';
    await Process.run('chmod', ['-R', '777', absPath]);
    if (Directory(absPath).existsSync()) {
      Directory(absPath).deleteSync(recursive: true);
    }
  });
}

// Helper function to create AtKeys from AtChopsKeys
AtKeys _getAtAuthKeysFromAtChopsKeys(AtChopsKeys atChopsKeys) {
  AtKeys atAuthKeys = AtKeys();

  if (atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.apkamPublicKey =
        AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.apkamPrivateKey =
        AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.defaultEncryptionPublicKey = AtBytes.fromString(
        atChopsKeys.atEncryptionKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.defaultEncryptionPrivateKey = AtBytes.fromString(
        atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.selfEncryptionKey?.key != null) {
    atAuthKeys.defaultSelfEncryptionKey =
        AtBytes.fromString(atChopsKeys.selfEncryptionKey!.key);
  }
  if (atChopsKeys.apkamSymmetricKey?.key != null) {
    atAuthKeys.apkamSymmetricKey =
        AtBytes.fromString(atChopsKeys.apkamSymmetricKey!.key);
  }

  return atAuthKeys;
}
