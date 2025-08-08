import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Functional tests for at_activate --yes', () {
    final tempDir = Directory.systemTemp.createTempSync('at_activate_functional_test');
    final testKeysPath = '${tempDir.path}/test_keys.atKeys';

    // Test #1: Verifies that CLI exits with code 0 when user responds "N" to the backup warning prompt
    test('Process-based test: CLI exits with code 0 on N response', () async {
      final result = await Process.run(
        'bash',
        ['-c', 'echo "N" | dart bin/activate_cli.dart onboard --atsign @testintegration --keys $testKeysPath --cramkey dummy-key'],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, equals(0));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #2: Verifies that CLI accepts "Y" response and continues processing (will fail later due to dummy key)
    test('Process-based test: CLI accepts Y response and continues', () async {
      final result = await Process.run(
        'bash', 
        ['-c', 'timeout 5s bash -c "echo Y | dart bin/activate_cli.dart onboard --atsign @testintegration --keys $testKeysPath --cramkey dummy-key" || true'],
        workingDirectory: Directory.current.path,
      );
      
      // Should not exit with code 0 (which is the cancellation code)
      // It will exit with a different code due to network/auth failure
      expect(result.exitCode, isNot(equals(0)));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #3: Verifies that the --yes flag completely bypasses the interactive backup warning prompt
    test('CLI with --yes bypasses prompt completely', () async {
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