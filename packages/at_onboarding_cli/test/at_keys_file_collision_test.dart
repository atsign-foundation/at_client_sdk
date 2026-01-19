import 'dart:io';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/util/home_directory_util.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysFileCollision tests', () {
    final atsign = '@collide67';
    late Directory tempDir;
    late String targetPath;
    late String content;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('at_keys_collision_test');
      targetPath = '${tempDir.path}/test.atKeys';
      content = 'test-content';
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writeToTempFile creates a secure temp file', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          targetPath: targetPath);
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
          targetPath: targetPath);

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
          targetPath: targetPath);
      final alternativePath = '$targetPath.alt';

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
          targetPath: targetPath);

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

      expect(File(tempPath).existsSync(), isFalse,
          reason: 'Temp file should be cleaned up on abort');
    });

    test('moveToTargetPath moves file and sets permissions', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          targetPath: targetPath);

      final movedFile =
          await AtKeysFileWriter.moveToTargetPath(tempPath, targetPath);

      expect(movedFile.path, equals(targetPath));
      expect(movedFile.existsSync(), isTrue);
      expect(File(tempPath).existsSync(), isFalse);
      expect(await movedFile.readAsString(), equals(content));
    });

    test('validate permissions on moveToTargetPath', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          targetPath: targetPath);
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
          targetPath: targetPath);

      if (!Platform.isWindows) {
        final stat = File(tempPath).statSync();
        expect(stat.mode & 0x1FF, 0x180);
      }
      await AtKeysFileWriter.cleanupTempFile(tempPath);
    });

    test('cleanupTempFile deletes the file', () async {
      final tempPath = await AtKeysFileWriter.writeToTempFile(content, atsign,
          targetPath: targetPath);
      expect(File(tempPath).existsSync(), isTrue);

      await AtKeysFileWriter.cleanupTempFile(tempPath);
      expect(File(tempPath).existsSync(), isFalse);
    });
  });
}
