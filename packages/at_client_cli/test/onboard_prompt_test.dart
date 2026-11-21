import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Functional tests for at_activate --yes', () {
    final tempDir =
        Directory.systemTemp.createTempSync('at_activate_functional_test');
    final testKeysPath = '${tempDir.path}/test_keys.atKeys';
    const backupPrompt = 'IMPORTANT - READ CAREFULLY';

    /// A loopback port nothing listens on, so the atDirectory there refuses
    /// the connection.
    Future<int> refusedPort() async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    }

    /// What at_activate does with a CRAM secret and [flags], against an
    /// atDirectory on the loopback interface that refuses the connection.
    Future<ProcessResult> cramOnboard(String flags) async => Process.run(
          'bash',
          [
            '-c',
            'timeout 20s env -u AT_REGISTRAR_API_KEY dart bin/at_activate.dart onboard --atsign @8incanteater --keys $testKeysPath --cramkey dummy-key $flags --root-server 127.0.0.1:${await refusedPort()} --max-retries 1'
          ],
          workingDirectory: Directory.current.path,
        );

    /// What at_activate does with no CRAM secret and no registrar API key set,
    /// with [answer] on its stdin and [flags], against a registrar on the
    /// loopback interface that refuses the connection.
    Future<ProcessResult> registrarOnboard(String answer, String flags) async =>
        Process.run(
          'bash',
          [
            '-c',
            'echo "$answer" | timeout 20s env -u AT_REGISTRAR_API_KEY dart bin/at_activate.dart onboard --atsign @8incanteater --keys $testKeysPath $flags --registrarUrl 127.0.0.1:${await refusedPort()}'
          ],
          workingDirectory: Directory.current.path,
        );

    void expectRegistrarAsked(ProcessResult result) {
      expect(
          '${result.stdout}${result.stderr}', contains('Requesting 127.0.0.1:'),
          reason: 'it went on to the loopback registrar, which refuses, so '
              'nothing leaves the machine');
      expect(result.exitCode, 1);
    }

    void expectNoPrompt(ProcessResult result) {
      expect(result.stdout, isNot(contains(backupPrompt)));
      expect('${result.stdout}${result.stderr}',
          contains('Could not reach the atDirectory at 127.0.0.1'),
          reason: 'it went on past the prompt, to the loopback atDirectory');
      expect(result.exitCode, 1);
    }

    // Test #1: test for exit 0 upon "N" response to backup key prompt
    test('Process-based test: CLI exits with code 0 on N response', () async {
      final result = await Process.run(
        'bash',
        [
          '-c',
          'echo "N" | env AT_REGISTRAR_API_KEY=app-key-3f9c71 dart bin/at_activate.dart onboard --atsign @8incanteater --keys $testKeysPath'
        ],
        workingDirectory: Directory.current.path,
      );
      expect(result.stdout, contains(backupPrompt),
          reason: 'the control: with neither --yes nor --cramkey, the prompt '
              'is shown');
      expect(result.exitCode, equals(0));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #2: test for exit code not 0 upon "Y" response to backup key prompt
    test('Process-based test: CLI accepts Y response and continues', () async {
      final result = await registrarOnboard('Y', '');

      expect(result.stdout, contains(backupPrompt));
      expectRegistrarAsked(result);
    }, timeout: Timeout(Duration(seconds: 30)));

    // Test #3: Tests that using the `--cramkey` implies `--yes` and bypasses the backup key prompt
    test('CLI with --cramkey bypasses prompt (implies --yes)', () async {
      expectNoPrompt(await cramOnboard(''));
    }, timeout: Timeout(Duration(seconds: 30)));

    // Test #4: Tests that using `--cramkey` with `--yes` is the same as using `--cramkey` without `--yes`
    test('CLI with --cramkey and --yes behaves the same as without --yes',
        () async {
      expectNoPrompt(await cramOnboard('--yes'));
    }, timeout: Timeout(Duration(seconds: 30)));

    // Test #5: Tests that using just `--yes` bypasses the backup key prompt
    test('CLI with --yes bypasses prompt and continues', () async {
      final result = await registrarOnboard('', '--yes');

      expect(result.stdout, isNot(contains(backupPrompt)));
      expectRegistrarAsked(result);
    }, timeout: Timeout(Duration(seconds: 30)));

    // runs after each individual test
    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
