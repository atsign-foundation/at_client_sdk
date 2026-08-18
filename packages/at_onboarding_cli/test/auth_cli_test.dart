import 'dart:io';

import 'package:args/args.dart' show ArgParserException;
import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart' show PqPosture;
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli_args.dart';

import 'package:at_onboarding_cli/src/util/at_file_util.dart';
import 'package:test/test.dart';
import 'at_onboarding_cli_test.dart';

void main() {
  final baseDirPath = 'test/keys';

  postureArgumentTests();

  group('A group of tests to verify write permission of apkam file path', () {
    final dirPath = '$baseDirPath/@alice-apkam-keys.atKeys';

    test(
        'ensureWritable throws PathAccessException if directory has read-only permissions',
        () async {
      final directory = Directory(dirPath);
      // Create the directory first to ensure it exists before calling isWritable.
      await directory.create(recursive: true);
      // Set permission to read only.
      await Process.run('chmod', ['444', baseDirPath]);
      expect(() => AtFileUtil.ensureWritable(File(dirPath)), throwsA(isA<AtException>()));
    });

    test(
        'ensureWritable doesnt throw if directory does not have a file already',
        () {
          expect(() => AtFileUtil.ensureWritable(File(dirPath)), returnsNormally);
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

/// `--posture`, which replaced `--signingAlgoType`.
///
/// Ruling 113's CLI section: honoured on **every** command, not activation
/// alone. `--signingAlgoType` silently did nothing on every command but
/// `onboard` ([#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161)),
/// which is what that ruling exists to stop happening again — so the rows
/// below check the argument reaches the parsers that were previously left out,
/// not just the one that always worked.
void postureArgumentTests() {
  final args = AuthCliArgs();

  group('the posture argument', () {
    test('every command parser accepts it, not activation alone', () {
      // The specific defect #2161 recorded. Each of these is a command a user
      // can run, and a posture means the same thing at all of them.
      final parsers = {
        'onboard': args.createOnboardCommandParser(),
        'status': args.createStatusCommandParser(),
        'enroll': args.createEnrollCommandParser(),
        'approve': args.createApproveCommandParser(),
        'deny': args.createDenyCommandParser(),
      };
      for (final entry in parsers.entries) {
        expect(entry.value.options.containsKey(AuthCliArgs.argNamePosture),
            isTrue,
            reason: '${entry.key} does not accept --posture, so a user who '
                'passes it there is silently ignored - the exact shape #2161 '
                'was filed for');
      }
    });

    test('the retired argument is gone from every one of them', () {
      for (final parser in [
        args.createOnboardCommandParser(),
        args.createStatusCommandParser(),
        args.createEnrollCommandParser(),
      ]) {
        expect(parser.options.containsKey('signingAlgoType'), isFalse,
            reason: 'it named the PKAM authentication key while reading like '
                'the data signing key, and every activation it could express '
                'is expressible as a posture');
      }
    });

    test('each name resolves to its posture, as raw strings', () {
      // Raw literals: these three strings are the CLI's published vocabulary,
      // and reading them back off the map they are defined in would follow an
      // accidental rename silently.
      expect(AuthCliArgs.postureNames.keys.toList(),
          ['legacy', 'pqReady', 'pqActive']);
      expect(AuthCliArgs.postureNames['legacy'], same(PqPosture.legacy));
      expect(AuthCliArgs.postureNames['pqReady'], same(PqPosture.pqReady));
      expect(AuthCliArgs.postureNames['pqActive'], same(PqPosture.pqActive));
    });

    test('an unnamed posture stays null rather than resolving to legacy', () {
      // "The caller said nothing" and "the caller asked for the default stage"
      // are the same value today and will not be after R-2. Collapsing them
      // here would leave this binary running the old default through the flip.
      final parsed = args.createStatusCommandParser().parse([]);
      expect(AuthCliArgs.postureIn(parsed), isNull);
    });

    test('a named posture is the one that comes back', () {
      final parsed =
          args.createStatusCommandParser().parse(['--posture', 'pqActive']);
      expect(AuthCliArgs.postureIn(parsed), same(PqPosture.pqActive));
    });

    test('an unknown posture is refused by the parser', () {
      expect(
          () => args.createStatusCommandParser().parse(['--posture', 'rollout2']),
          throwsA(isA<ArgParserException>().having((e) => e.message, 'message',
              contains('not an allowed value'))),
          reason: 'the old stage names are exactly what a user would try, and '
              'a silently accepted one would run the default stage');
    });
  });
}
