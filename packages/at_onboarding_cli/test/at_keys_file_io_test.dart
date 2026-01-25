import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:test/test.dart';

void main() {
  group('Validate AtKeysFileWriter and CollisionAwareFileAtKeysIO behaviour',
      () {
    late Directory tempDir;
    late String tempDirPath;
    late AtKeys testKeys;
    late String testContent;

    setUp(() async {
      // Create local test directory instead of system temp
      tempDirPath = 'test/at_keys_io_test_storage';
      tempDir = Directory(tempDirPath);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      testContent = 'test-content';

      // Create test keys with valid 32-byte (256-bit) base64 strings for AES
      testKeys = AtKeys()
        ..apkamPublicKey =
            AtBytes.fromString('c29tZSBwa2FtIHB1YmxpYyBrZXkgZm9yIHRlc3Rpbmc=')
        ..apkamPrivateKey =
            AtBytes.fromString('c29tZSBwa2FtIHByaXZhdGUga2V5IGZvciB0ZXN0aW5n')
        ..defaultEncryptionPublicKey =
            AtBytes.fromString('c29tZSBlbmNyeXB0aW9uIHB1YmxpYyBrZXkgdGVzdA==')
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString('c29tZSBlbmNyeXB0aW9uIHByaXZhdGUga2V5IHRlc3Q=')
        ..defaultSelfEncryptionKey =
            AtBytes.fromString('YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=')
        ..apkamSymmetricKey =
            AtBytes.fromString('YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('AtKeysFileWriter - ', () {
      test('writeKeys writes content and sets permissions', () async {
        final targetPath = '$tempDirPath/test.atKeys';
        final finalPath = await AtKeysFileWriter.writeKeys(
          testContent,
          targetPath,
          (context) => AtKeysFileCollisionAbort(),
        );

        final file = File(finalPath);
        expect(file.existsSync(), isTrue);
        expect(await file.readAsString(), equals(testContent));
        expect(finalPath, equals(targetPath));

        if (!Platform.isWindows) {
          final stat = file.statSync();
          expect(stat.mode & 0x1FF, 0x180); // 600 in octal
        }
      });

      test('writeKeys calls handler on collision and returns alternative',
          () async {
        final targetPath = '$tempDirPath/collision.atKeys';
        File(targetPath).writeAsStringSync('existing-content');

        final alternativePath = '$targetPath.alt.atKeys';

        final finalPath = await AtKeysFileWriter.writeKeys(
          testContent,
          targetPath,
          (context) {
            return AtKeysFileCollisionUseAlternative(alternativePath);
          },
        );

        expect(finalPath, equals(alternativePath));
        expect(File(finalPath).existsSync(), isTrue);
        expect(await File(finalPath).readAsString(), equals(testContent));
      });

      test('writeKeys throws AtKeysFileExistsException on abort', () async {
        final targetPath = '$tempDirPath/abort.atKeys';
        File(targetPath).writeAsStringSync('existing-content');

        await expectLater(
          AtKeysFileWriter.writeKeys(
            testContent,
            targetPath,
            (context) => AtKeysFileCollisionAbort(customMessage: 'Abort test'),
          ),
          throwsA(isA<AtKeysFileExistsException>()
              .having((e) => e.message, 'message', contains('Abort test'))),
        );
      });

      test('writeKeys retries when handler returns another colliding path',
          () async {
        final collidingPath1 = '$tempDirPath/collide1.atKeys';
        final collidingPath2 = '$tempDirPath/collide2.atKeys';
        final successPath = '$tempDirPath/success.atKeys';

        File(collidingPath1).writeAsStringSync('dummyText');
        File(collidingPath2).writeAsStringSync('dummyText');

        int callCount = 0;
        final resultPath = await AtKeysFileWriter.writeKeys(
          testContent,
          collidingPath1,
          (context) {
            callCount++;
            if (callCount == 1) {
              return AtKeysFileCollisionUseAlternative(collidingPath2);
            }
            return AtKeysFileCollisionUseAlternative(successPath);
          },
        );

        expect(resultPath, equals(successPath));
        expect(callCount, equals(2));
        expect(File(successPath).existsSync(), isTrue);
      });
    });

    group('CollisionAwareFileAtKeysIo - ', () {
      late CollisionAwareFileAtKeysIo keysIo;

      setUp(() {
        keysIo = CollisionAwareFileAtKeysIo(
          filePath: (atSign) => '$tempDirPath/$atSign.atKeys',
          collisionHandler: AtKeysFileCollisionHandlers.abortOnCollisionHandler,
        );
      });

      test('write() creates keys file successfully', () async {
        const atSign = '@alice';
        await keysIo.write(atSign, testKeys);

        final file = File('$tempDirPath/$atSign.atKeys');
        expect(file.existsSync(), isTrue);

        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        expect(decoded[AuthKeyType.selfEncryptionKey], isNotEmpty);
      });

      test('write() includes enrollmentId in keys file', () async {
        const atSign = '@bob_enroll';
        const enrollmentId = 'test-enrollment-id-123';
        testKeys.enrollmentId = enrollmentId;

        await keysIo.write(atSign, testKeys);

        final file = File('$tempDirPath/$atSign.atKeys');
        expect(file.existsSync(), isTrue);

        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        expect(decoded['enrollmentId'], equals(enrollmentId));
      });

      test('read() reads and decrypts keys file', () async {
        const atSign = '@eve';
        await keysIo.write(atSign, testKeys);

        final readKeys = await keysIo.read(atSign);
        expect(readKeys.defaultSelfEncryptionKey!.toString(),
            equals(testKeys.defaultSelfEncryptionKey!.toString()));
      });

      test('writeKeys() encrypts with passphrase when provided', () async {
        final targetPath = '$tempDirPath/@pikachu.atKeys';
        const passPhrase = 'test-password-123';

        await CollisionAwareFileAtKeysIo.writeKeys(
          atKeys: testKeys,
          atSign: '@pikachu',
          targetPath: targetPath,
          passPhrase: passPhrase,
          hashingAlgoType: HashingAlgoType.argon2id,
        );

        final content = await File(targetPath).readAsString();
        final decoded = jsonDecode(content);

        expect(decoded, isA<Map<String, dynamic>>());
        expect(decoded.containsKey('content'), isTrue);
        expect(decoded.containsKey('iv'), isTrue);
        expect(decoded['hashingAlgoType'], equals('argon2id'));
      });
    });
  });
}
