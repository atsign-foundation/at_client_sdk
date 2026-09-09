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
      expect(() => AtFileUtil.ensureWritable(File(dirPath)),
          throwsA(isA<AtException>()));
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

/// Tests that `--posture` is honoured on every command, not on activation
/// alone.
///
/// A parser that accepts the argument is not a client that runs under it, so
/// both halves are asserted.
void postureArgumentTests() {
  final args = AuthCliArgs();

  group('the posture argument', () {
    test('every command parser accepts it, not activation alone', () {
      final parsers = {
        'onboard': args.createOnboardCommandParser(),
        'status': args.createStatusCommandParser(),
        'enroll': args.createEnrollCommandParser(),
        'approve': args.createApproveCommandParser(),
        'deny': args.createDenyCommandParser(),
      };
      for (final entry in parsers.entries) {
        expect(
            entry.value.options.containsKey(AuthCliArgs.argNamePosture), isTrue,
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

      // NOTE: latent while an unset posture and legacy are the same value —
      // this cannot fail until the default moves, and the row below is what
      // discriminates until then.
      expect(AuthCliArgs.preferenceUnder(null).posture,
          same(AtOnboardingPreference().posture));
    });

    test(
        'a posture constant is named where the roles are decided, nowhere else',
        () {
      // NOTE: a `?? PqPosture.legacy` where a preference is built makes an
      // unset --posture stop meaning "no opinion", so only the file that
      // decides the role defaults may name a posture constant.
      final byFile = <String, List<String>>{};
      for (final path in const [
        'lib/src/cli/auth_cli.dart',
        'lib/src/cli/auth_cli_args.dart',
        'lib/src/util/create_at_client_cli.dart',
      ]) {
        final lines = File(path).readAsLinesSync();
        expect(lines, isNotEmpty,
            reason: '$path did not read; a rail over an '
                'empty file passes for the wrong reason');
        for (final line in lines) {
          final code = line.trim();
          if (code.startsWith('//')) continue;
          if (RegExp(r'PqPosture\.(legacy|pqReady|pqActive)').hasMatch(code)) {
            (byFile[path] ??= <String>[]).add(code);
          }
        }
      }
      for (final path in const [
        'lib/src/cli/auth_cli.dart',
        'lib/src/util/create_at_client_cli.dart',
      ]) {
        expect(byFile[path] ?? const <String>[], isEmpty,
            reason: 'a command and a client factory take the posture they are '
                'handed; naming one here restates a default where nothing '
                'reviews it:\n${(byFile[path] ?? const []).join('\n')}');
      }
      final args = byFile['lib/src/cli/auth_cli_args.dart'] ?? const <String>[];
      expect(args, hasLength(6),
          reason: 'expected the three postureNames entries plus the three '
              'lines that decide a role default — the legacy an enroller '
              'falls to, the legacy an approver refuses, and the pqReady it '
              'falls to. Anything else is a fourth opinion about what a '
              'command runs at:\n${args.join('\n')}');
    });

    test('every command that builds a client passes the posture to it', () {
      // NOTE: read from source because driving each command needs an atServer
      // per row.
      final source = File('lib/src/cli/auth_cli.dart').readAsStringSync();
      final calls =
          RegExp(r'(?<![A-Za-z_])createAtClient\(').allMatches(source).toList();
      expect(calls, isNotEmpty,
          reason: 'if this finds nothing the rest of the row proves nothing');

      final without = <int>[];
      for (final call in calls) {
        final end = source.indexOf(');', call.start);
        if (!source.substring(call.start, end).contains('posture:')) {
          without
              .add('\n'.allMatches(source.substring(0, call.start)).length + 1);
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
      // NOTE: raw literals — these three strings are the CLI's published
      // vocabulary, so reading them back off their own map would follow a
      // rename silently.
      expect(AuthCliArgs.postureNames.keys.toList(),
          ['legacy', 'pqReady', 'pqActive']);
      expect(AuthCliArgs.postureNames['legacy'], same(PqPosture.legacy));
      expect(AuthCliArgs.postureNames['pqReady'], same(PqPosture.pqReady));
      expect(AuthCliArgs.postureNames['pqActive'], same(PqPosture.pqActive));
    });

    test('an unnamed posture stays null rather than resolving to legacy', () {
      // NOTE: `postureIn` keeps "the caller said nothing" distinct from any
      // stage name; the two roles below default it in opposite directions, so
      // collapsing it here would make one of them unstateable.
      final parsed = args.createStatusCommandParser().parse([]);
      expect(AuthCliArgs.postureIn(parsed), isNull);
    });

    test('an enroller with no --posture runs legacy, and says so', () {
      final parsed = args.createEnrollCommandParser().parse([]);
      final resolved = AuthCliArgs.postureForEnroller(parsed);
      expect(resolved.posture, same(PqPosture.legacy),
          reason: 'the keys onboard and enroll write have to stay usable by a '
              'legacy app, and a default invocation puts no post-quantum '
              'machinery in the picture');
      expect(resolved.notice, isNotNull,
          reason: 'a default this consequential is announced, or a caller who '
              'wanted a post-quantum enrolment finds out when a peer cannot '
              'read something');
      expect(resolved.notice, contains('legacy'));
    });

    test('an enroller that names a posture gets it, with nothing announced',
        () {
      final parsed =
          args.createEnrollCommandParser().parse(['--posture', 'pqActive']);
      final resolved = AuthCliArgs.postureForEnroller(parsed);
      expect(resolved.posture, same(PqPosture.pqActive));
      expect(resolved.notice, isNull,
          reason: 'nothing was defaulted, so there is nothing to tell anyone');
    });

    test('an approver with no --posture runs pqReady', () {
      final parsed = args.createStatusCommandParser().parse([]);
      expect(AuthCliArgs.postureForApprover(parsed), same(PqPosture.pqReady),
          reason: 'approving a post-quantum enrolment means minting a '
              'symmetric key and encapsulating it to the requester\'s key '
              'package, which needs the post-quantum providers');
    });

    test('an approver naming legacy is refused, and told why', () {
      final parsed =
          args.createStatusCommandParser().parse(['--posture', 'legacy']);
      expect(
          () => AuthCliArgs.postureForApprover(parsed),
          throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
              contains('configures no post-quantum providers'))),
          reason: 'at_client already refuses such an approval before it '
              'reaches the atServer; refusing the argument turns that runtime '
              'failure into a usage message');
    });

    test('a bare invocation is refused rather than treated as onboard',
        () async {
      // NOTE: `wrappedMain` reaches the refusal before any command is parsed,
      // so this needs no atServer.
      expect(await wrappedMain(['-a', '@alice']), 1);
      // The positive control.
      expect(await wrappedMain(['--version']), 0,
          reason: 'a leading option that is not a command must still be '
              'served, or the refusal has swallowed --version and --help too');
    });

    test('an approver may still name pqActive', () {
      final parsed =
          args.createStatusCommandParser().parse(['--posture', 'pqActive']);
      expect(AuthCliArgs.postureForApprover(parsed), same(PqPosture.pqActive),
          reason: 'pqReady is the default rather than the ceiling — what is '
              'refused is dropping BELOW what an approver needs');
    });

    test('a named posture is the one that comes back', () {
      final parsed =
          args.createStatusCommandParser().parse(['--posture', 'pqActive']);
      expect(AuthCliArgs.postureIn(parsed), same(PqPosture.pqActive));
    });

    test('an unknown posture is refused by the parser', () {
      expect(
          () =>
              args.createStatusCommandParser().parse(['--posture', 'rollout2']),
          throwsA(isA<ArgParserException>().having(
              (e) => e.message, 'message', contains('not an allowed value'))),
          reason: 'the old stage names are exactly what a user would try, and '
              'a silently accepted one would run the default stage');
    });
  });
}
