import 'dart:io';

import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/util/home_directory_util.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysFileCollision tests', () {
    final atsign = '@collide67';
    late String tempDir;
    late Directory tempDirObj;
    late String targetPath;
    late String content;

    setUp(() {
      tempDirObj =
          Directory.systemTemp.createTempSync('at_keys_collision_test');
      tempDir = tempDirObj.path;
      targetPath = '$tempDir/test.atKeys';
      content = 'test-content';
    });

    tearDown(() {
      if (tempDirObj.existsSync()) {
        tempDirObj.deleteSync(recursive: true);
      }
    });

    test('writeToTempFile creates a secure temp file', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);
      final file = File(tempPath);

      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), equals(content));
      expect(tempPath, contains(atsign));
      expect(tempPath, endsWith('.tmp'));

      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test('ensure tmp file is created at the fallback location', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign);
      expect(tempPath, startsWith(HomeDirectoryUtil.getDefaultTempDir()));
      expect(File(tempPath).existsSync(), isTrue);
      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test('handleTargetCollision returns targetPath if no collision', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);

      final finalPath = await AtKeysFileWriter.handleTargetCollision(
        tempPath,
        targetPath,
        content,
        (context) => AtKeysFileCollisionAbort(), // Should not be called
      );

      expect(finalPath, equals(targetPath));
      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test(
        'handleTargetCollision calls handler on collision and returns alternative',
        () async {
      // Create the target file to cause collision
      File(targetPath).writeAsStringSync('existing-content');

      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);
      final alternativePath = '$targetPath.atKeys';

      final finalPath = await AtKeysFileWriter.handleTargetCollision(
        tempPath,
        targetPath,
        content,
        (context) {
          expect(context.targetFilePath, equals(targetPath));
          expect(context.keysContent, equals(content));
          return AtKeysFileCollisionUseAlternative(alternativePath);
        },
      );

      expect(finalPath, equals(alternativePath));
      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test('handleTargetCollision throws AtKeysFileExistsException on abort',
        () async {
      File(targetPath).writeAsStringSync('existing-content');
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);

      expect(
        () => AtKeysFileWriter.handleTargetCollision(
          tempPath,
          targetPath,
          content,
          (context) => AtKeysFileCollisionAbort(customMessage: 'Abort test'),
        ),
        throwsA(isA<AtKeysFileExistsException>()
            .having((e) => e.message, 'message', contains('Abort test'))),
      );
    });

    test('moveToTargetPath moves file and sets permissions', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);

      final movedFile =
          await AtKeysFileWriter.moveToTargetPath(tempPath, targetPath);

      expect(movedFile.path, equals(targetPath));
      expect(movedFile.existsSync(), isTrue);
      expect(File(tempPath).existsSync(), isFalse);
      expect(await movedFile.readAsString(), equals(content));
    });

    test('validate permissions on moveToTargetPath', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);
      final movedFile =
          await AtKeysFileWriter.moveToTargetPath(tempPath, targetPath);

      if (!Platform.isWindows) {
        final stat = movedFile.statSync();
        // Check if permissions are 600 (rw-------)
        // Mask with 0x1FF (777 in octal) to get permission bits
        // 0x180 is 600 in octal
        expect(stat.mode & 0x1FF, 0x180);
      }
    });

    test('validate permissions on create temp file', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);

      if (!Platform.isWindows) {
        final stat = File(tempPath).statSync();
        expect(stat.mode & 0x1FF, 0x180);
      }
      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test(
        'handleTargetCollision retries when handler returns another colliding path',
        () async {
      final collidingPath1 = '$tempDir/collide1.atKeys';
      final collidingPath2 = '$tempDir/collide2.atKeys';
      final finalPath = '$tempDir/success.atKeys';

      File(collidingPath1).writeAsStringSync('c1');
      File(collidingPath2).writeAsStringSync('c2');

      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);

      int callCount = 0;
      final resultPath = await AtKeysFileWriter.handleTargetCollision(
        tempPath,
        collidingPath1,
        content,
        (context) {
          callCount++;
          if (callCount == 1) {
            return AtKeysFileCollisionUseAlternative(collidingPath2);
          }
          return AtKeysFileCollisionUseAlternative(finalPath);
        },
      );

      expect(resultPath, equals(finalPath));
      expect(callCount, equals(2));
      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test('handleTargetCollision aborts after maxAttempts', () async {
      File(targetPath).writeAsStringSync('exists');
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);

      await expectLater(
        AtKeysFileWriter.handleTargetCollision(
          tempPath,
          targetPath,
          content,
          (context) => AtKeysFileCollisionUseAlternative(targetPath),
        ),
        throwsA(isA<AtKeysFileExistsException>().having(
            (e) => e.message, 'message', contains('Too many file collisions'))),
      );
    });

    test('abortOnCollision handler returns AtKeysFileCollisionAbort', () {
      final ctx = AtKeysFileCollisionContext(
        targetFilePath: '/test/path.atKeys',
        keysContent: 'test-keys-content',
      );

      final result = AtKeysFileCollisionHandlers.abortOnCollision(ctx);

      expect(result, isA<AtKeysFileCollisionAbort>());
      expect((result as AtKeysFileCollisionAbort).customMessage,
          contains('/test/path.atKeys'));
    });

    test('handleTargetCollision works with async handler', () async {
      File(targetPath).writeAsStringSync('existing-content');
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);
      final alternativePath = '$targetPath.async';

      Future<AtKeysFileCollisionUseAlternative> asyncHandler (context) async {
        // Simulate async operation
        await Future.delayed(Duration(milliseconds: 10));
        return AtKeysFileCollisionUseAlternative(alternativePath);
      }

      // Use an async handler that returns a Future
      final finalPath = await AtKeysFileWriter.handleTargetCollision(
        tempPath,
        targetPath,
        content,
          (context) => asyncHandler(context),
      );

      expect(finalPath, equals(alternativePath));
      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test('cleanupTempFile deletes existing file', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          tempFilePath: targetPath);
      expect(File(tempPath).existsSync(), isTrue);

      await AtKeysFileWriter.cleanupTempFile(tempPath);

      expect(File(tempPath).existsSync(), isFalse);
    });

    test('cleanupTempFile is idempotent for non-existent file', () async {
      final nonExistentPath = '$tempDir/non_existent.tmp';

      await AtKeysFileWriter.cleanupTempFile(nonExistentPath);
    });
  });
}
