import 'dart:io';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysFileCollision tests', () {
    late String tempDir;
    late String targetPath;
    late String content;
    late Directory tempDirObj;

    setUp(() {
      tempDirObj = Directory.systemTemp.createTempSync('at_keys_collision_test');
      tempDir = tempDirObj.path;
      targetPath = '$tempDir/test.atKeys';
      content = 'test-content';
    });

    tearDown(() {
      if (tempDirObj.existsSync()) {
        tempDirObj.deleteSync(recursive: true);
      }
    });

    test('writeKeys writes content and sets permissions', () async {
      final finalPath = await AtKeysFileWriter.writeKeys(
        content,
        targetPath,
        (context) => AtKeysFileCollisionAbort(), // Should not be called
      );

      final file = File(finalPath);
      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), equals(content));
      expect(finalPath, equals(targetPath));

      if (!Platform.isWindows) {
        final stat = file.statSync();
        expect(stat.mode & 0x1FF, 0x180); // 600 in octal
      }
    });

    test('writeKeys calls handler on collision and returns alternative', () async {
      // Create the target file to cause collision
      File(targetPath).writeAsStringSync('existing-content');

      final alternativePath = '$targetPath.alt';

      final finalPath = await AtKeysFileWriter.writeKeys(
        content,
        targetPath,
        (context) {
          expect(context.targetFilePath, equals(targetPath));
          expect(context.keysContent, equals(content));
          return AtKeysFileCollisionUseAlternative(alternativePath);
        },
      );

      expect(finalPath, equals(alternativePath));
      expect(File(finalPath).existsSync(), isTrue);
      expect(await File(finalPath).readAsString(), equals(content));
    });

    test('writeKeys throws AtKeysFileExistsException on abort', () async {
      File(targetPath).writeAsStringSync('existing-content');

      expectLater(
        AtKeysFileWriter.writeKeys(
          content,
          targetPath,
          (context) => AtKeysFileCollisionAbort(customMessage: 'Abort test'),
        ),
        throwsA(isA<AtKeysFileExistsException>()
            .having((e) => e.message, 'message', contains('Abort test'))),
      );
    });

    test('writeKeys retries when handler returns another colliding path', () async {
      final collidingPath1 = '$tempDir/collide1.atKeys';
      final collidingPath2 = '$tempDir/collide2.atKeys';
      final finalPath = '$tempDir/success.atKeys';

      File(collidingPath1).writeAsStringSync('c1');
      File(collidingPath2).writeAsStringSync('c2');

      int callCount = 0;
      final resultPath = await AtKeysFileWriter.writeKeys(
        content,
        collidingPath1,
        (context) {
          callCount++;
          if (callCount == 1) return AtKeysFileCollisionUseAlternative(collidingPath2);
          return AtKeysFileCollisionUseAlternative(finalPath);
        },
      );

      expect(resultPath, equals(finalPath));
      expect(callCount, equals(2));
      expect(File(finalPath).existsSync(), isTrue);
    });

    test('writeKeys aborts after maxAttempts', () async {
      File(targetPath).writeAsStringSync('exists');

      await expectLater(
        AtKeysFileWriter.writeKeys(
          content,
          targetPath,
          (context) => AtKeysFileCollisionUseAlternative(targetPath), // Loop!
        ),
        throwsA(isA<AtKeysFileExistsException>().having(
            (e) => e.message, 'message', contains('Too many file collisions'))),
      );
    });

    test('writeKeys works with async handler', () async {
      File(targetPath).writeAsStringSync('existing-content');
      final alternativePath = '$targetPath.async';

      final finalPath = await AtKeysFileWriter.writeKeys(
        content,
        targetPath,
        (context) async {
          await Future.delayed(Duration(milliseconds: 10));
          return AtKeysFileCollisionUseAlternative(alternativePath);
        },
      );

      expect(finalPath, equals(alternativePath));
      expect(File(finalPath).existsSync(), isTrue);
    });
  });
}