import 'dart:io';

import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:test/test.dart';

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

  tearDown(() async {
    // Set full permissions to delete the directory.
    await Process.run('chmod', ['777', baseDirPath]);
    Directory(baseDirPath).deleteSync(recursive: true);
  });
}
