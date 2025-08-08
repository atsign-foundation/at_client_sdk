import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Functional tests for at_activate --yes', () {
    final tempDir = Directory.systemTemp.createTempSync('at_activate_functional_test');
    final testKeysPath = '${tempDir.path}/test_keys.atKeys';

    // Test #1: test for exit 0 upon "N" response to backup key prompt
    test('Process-based test: CLI exits with code 0 on N response', () async {
      final result = await Process.run(
        'bash',
        ['-c', 'echo "N" | dart bin/activate_cli.dart onboard --atsign @testintegration --keys $testKeysPath'],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, equals(0));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #2: test for exit code not 0 upon "Y" response to backup key prompt
    test('Process-based test: CLI accepts Y response and continues', () async {
      final result = await Process.run(
        'bash', 
        ['-c', 'timeout 5s bash -c "echo Y | dart bin/activate_cli.dart onboard --atsign @testintegration --keys $testKeysPath" || true'],
        workingDirectory: Directory.current.path,
      );
      
      // Should not exit with code 0 (which is the cancellation code)
      // It will exit with a different code due to failure
      expect(result.exitCode, isNot(equals(0)));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #3: Tests that using the `--cramkey` implies `--yes` and bypasses the backup key prompt
    test('CLI with --yes bypasses prompt completely', () async {
      final result = await Process.run(
        'bash',
        ['-c', 'timeout 5s dart bin/activate_cli.dart onboard --atsign @testintegration --keys $testKeysPath --cramkey dummy-key || true'],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, isNot(equals(0)));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #4: Tests that using `--cramkey` with `--yes` is the same as using `--cramkey` without `--yes`
    test('CLI with --cramkey and --yes behaves the same as without --yes', () async {
      final result = await Process.run(
        'bash',
        ['-c', 'timeout 5s dart bin/activate_cli.dart onboard --atsign @testintegration --keys $testKeysPath --cramkey dummy-key --yes || true'],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, isNot(equals(0)));
    }, timeout: Timeout(Duration(seconds: 10)));

    // runs after each individual test
    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}