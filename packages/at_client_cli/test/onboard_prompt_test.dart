import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

/// Points at_activate at a registrar and a root nothing listens on, so a run
/// that gets past the prompt cannot reach the production registrar (which
/// would email whoever owns the atSign) or atDirectory.
const _offline = ['-g', '127.0.0.1:9', '--root-server', '127.0.0.1'];

/// What at_activate run with [args] and no stdin writes until it says it is
/// onboarding and a moment more, for a prompt to follow, or until it has run
/// for 20 seconds; it is then killed.
///
/// NOTE: without a reply the backup prompt never ends, so a run that shows it
/// cannot be told by its exit code from one still onboarding.
Future<({String stdout, String stderr})> runPastPrompt(
    List<String> args) async {
  final process =
      await Process.start('dart', ['bin/at_activate.dart', ...args]);
  await process.stdin.close();
  final out = StringBuffer();
  final err = StringBuffer();
  final onboarding = Completer<void>();
  process.stdout.transform(utf8.decoder).listen(out.write);
  process.stderr.transform(utf8.decoder).listen((text) {
    err.write(text);
    if (!onboarding.isCompleted &&
        err.toString().contains('Onboarding your atSign')) {
      onboarding.complete();
    }
  });
  await Future.any([
    onboarding.future.then((_) => Future.delayed(Duration(seconds: 1))),
    process.exitCode,
    Future.delayed(Duration(seconds: 20)),
  ]);
  process.kill();
  await process.exitCode;
  return (stdout: out.toString(), stderr: err.toString());
}

/// [output] got as far as onboarding, and showed no backup prompt on the way.
void expectNoPrompt(({String stdout, String stderr}) output) {
  expect(output.stderr, contains('Onboarding your atSign'),
      reason: 'it got as far as onboarding');
  expect(output.stdout, isNot(contains('losing these keys')),
      reason: 'the backup prompt was skipped');
}

void main() {
  group('Functional tests for at_activate --yes', () {
    final tempDir =
        Directory.systemTemp.createTempSync('at_activate_functional_test');
    final testKeysPath = '${tempDir.path}/test_keys.atKeys';

    // Test #1: test for exit 0 upon "N" response to backup key prompt
    test('Process-based test: CLI exits with code 0 on N response', () async {
      final result = await Process.run(
        'bash',
        [
          '-c',
          'echo "N" | dart bin/at_activate.dart onboard --atsign @8incanteater --keys $testKeysPath'
        ],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, equals(0));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #2: test for exit code not 0 upon "Y" response to backup key prompt
    test('Process-based test: CLI accepts Y response and continues', () async {
      final result = await Process.run(
        'bash',
        [
          '-c',
          'timeout 5s bash -c "echo Y | dart bin/at_activate.dart onboard --atsign @8incanteater --keys $testKeysPath ${_offline.join(' ')}"'
        ],
        workingDirectory: Directory.current.path,
      );

      // Should not exit with code 0 (which is the cancellation code)
      // It will exit with a different code due to failure
      expect(result.exitCode, isNot(equals(0)));
    }, timeout: Timeout(Duration(seconds: 10)));

    // Test #3: Tests that using the `--cramkey` implies `--yes` and bypasses the backup key prompt
    test('CLI with --cramkey bypasses prompt (implies --yes)', () async {
      expectNoPrompt(await runPastPrompt([
        'onboard', '--atsign', '@8incanteater', '--keys', testKeysPath, //
        '--cramkey', 'dummy-key', ..._offline,
      ]));
    }, timeout: Timeout(Duration(seconds: 30)));

    // Test #4: Tests that using `--cramkey` with `--yes` is the same as using `--cramkey` without `--yes`
    test('CLI with --cramkey and --yes behaves the same as without --yes',
        () async {
      expectNoPrompt(await runPastPrompt([
        'onboard', '--atsign', '@8incanteater', '--keys', testKeysPath, //
        '--cramkey', 'dummy-key', '--yes', ..._offline,
      ]));
    }, timeout: Timeout(Duration(seconds: 30)));

    // Test #5: Tests that using just `--yes` bypasses the backup key prompt
    test('CLI with --yes bypasses prompt and continues', () async {
      expectNoPrompt(await runPastPrompt([
        'onboard', '--atsign', '@8incanteater', '--keys', testKeysPath, //
        '--yes', ..._offline,
      ]));
    }, timeout: Timeout(Duration(seconds: 30)));

    // runs after each individual test
    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
