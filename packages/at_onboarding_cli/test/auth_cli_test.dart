import 'dart:io';

import 'package:args/args.dart' show ArgParserException;
import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart' show PqPosture;
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli_args.dart';

import 'package:at_onboarding_cli/src/util/at_file_util.dart';
import 'package:at_onboarding_cli/src/util/at_onboarding_preference.dart';
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
/// which is what that ruling exists to stop happening again.
///
/// ⚠️ **A parser that accepts an argument is not a client that runs under
/// it**, and for a day this file only checked the first. `--posture` reached
/// every parser while only `onboard` and `enroll` read the value — the other
/// twelve commands built their client through `createAtClient`, which named no
/// posture — so the argument reproduced the exact no-op it replaced, and these
/// rows were green throughout. The last two rows are the missing half.
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

    test('a named posture reaches the preference with its axes', () {
      final asked = AuthCliArgs.preferenceUnder(PqPosture.pqActive);
      expect(asked.posture, same(PqPosture.pqActive));
      expect(asked.authenticationKeyAlgorithm, SigningAlgoType.mldsa65,
          reason: 'the axes have to come with it, or naming a posture buys '
              'nothing');

      // Latent, and deliberately kept as such: "the caller said nothing" and
      // "the caller asked for legacy" are the same VALUE today, so this cannot
      // fail now however the CLI resolves an unset argument. It arms itself at
      // R-2, when the default moves and a CLI that restated `PqPosture.legacy`
      // starts running the old stage through the flip. What discriminates
      // today is the row below.
      expect(AuthCliArgs.preferenceUnder(null).posture,
          same(AtOnboardingPreference().posture));
    });

    test('the CLI names a posture constant in exactly one place', () {
      // `?? PqPosture.legacy` where a preference is built is how an unset
      // --posture quietly stopped meaning "no opinion", and the assertion
      // above cannot see it while legacy is still the default. The three
      // entries of `postureNames` are the whole legitimate vocabulary; a
      // fourth mention in code is a construction site restating a default.
      final named = <String>[];
      for (final path in const [
        'lib/src/cli/auth_cli.dart',
        'lib/src/cli/auth_cli_args.dart',
        'lib/src/util/create_at_client_cli.dart',
      ]) {
        final lines = File(path).readAsLinesSync();
        expect(lines, isNotEmpty, reason: '$path did not read; a rail over an '
            'empty file passes for the wrong reason');
        for (final line in lines) {
          final code = line.trim();
          if (code.startsWith('//')) continue;
          if (RegExp(r'PqPosture\.(legacy|pqReady|pqActive)').hasMatch(code)) {
            named.add('$path | $code');
          }
        }
      }
      expect(named, hasLength(3),
          reason: 'expected only the three postureNames entries, got:\n'
              '${named.join('\n')}');
      expect(named.every((l) => l.contains('auth_cli_args.dart')), isTrue,
          reason: 'the map is the one place a posture constant belongs:\n'
              '${named.join('\n')}');
    });

    test('every command that builds a client passes the posture to it', () {
      // The half a parser check cannot reach. `createAtClient` serves every
      // command except onboard and enroll, and a call site that omits the
      // argument leaves that command silently at the built-in default however
      // loudly the user named one. Read from source because the alternative —
      // driving each command — needs an atServer per row.
      final source = File('lib/src/cli/auth_cli.dart').readAsStringSync();
      final calls = RegExp(r'(?<![A-Za-z_])createAtClient\(')
          .allMatches(source)
          .toList();
      expect(calls, isNotEmpty,
          reason: 'if this finds nothing the rest of the row proves nothing');

      final without = <int>[];
      for (final call in calls) {
        final end = source.indexOf(');', call.start);
        if (!source.substring(call.start, end).contains('posture:')) {
          without.add('\n'.allMatches(source.substring(0, call.start)).length + 1);
        }
      }
      expect(without, isEmpty,
          reason: 'auth_cli.dart lines $without call createAtClient without a '
              'posture, so those commands ignore --posture');
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
