import 'dart:io';

import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:test/test.dart';

void main() {
  final baseDirPath = 'test/keys';

  setUpAll(() {
    Directory(baseDirPath).createSync(recursive: true);
  });

  group('A group of tests to verify write permission of apkam file path', () {
    final dirPath = '$baseDirPath/@alice-apkam-keys.atKeys';

    test(
        'A test to verify isWritable returns false if directory has read-only permissions',
        () async {
      if (Directory(baseDirPath).existsSync()) {
        await Directory(baseDirPath).delete(recursive: true);
      }
      // Create the base directory
      final directory = Directory(baseDirPath);
      await directory.create(recursive: true);

      // Set permission to read only for the directory itself
      await Process.run('chmod', ['444', baseDirPath]);

      // Attempt to create a NEW file within the read-only directory
      final newFilePath = '$baseDirPath/new_read_only_test.atKeys';
      expect(canCreateFile(File(newFilePath)), false);
    });

    test(
        'A test verify isWritable returns true if directory does not have a file already',
        () async {
      // Ensure the base directory exists and is writable for this test
      if (Directory(baseDirPath).existsSync()) {
        await Directory(baseDirPath).delete(recursive: true);
      }
      await Directory(baseDirPath).create(recursive: true);

      // Ensure permissions are normal (777) for this test
      await Process.run('chmod', ['777', baseDirPath]);

      final newFilePath = '$baseDirPath/another_new_file.atKeys';
      expect(canCreateFile(File(newFilePath)), true);
    });
  });

  tearDown(() async {
    // Set full permissions to delete the directory.
    if (Directory(baseDirPath).existsSync()) {
      await Process.run('chmod', ['777', baseDirPath]); // Ensure writable for deletion
      Directory(baseDirPath).deleteSync(recursive: true);
    }
  });
}
