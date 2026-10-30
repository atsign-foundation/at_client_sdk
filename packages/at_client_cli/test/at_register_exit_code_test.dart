import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// at_register's exit code, observed by running it against a registrar on the
/// loopback interface.
///
/// Catalogue: features/at_client_cli/at_register_exit_codes.feature
void main() {
  late Directory home;

  setUp(() => home =
      Directory.systemTemp.createTempSync('at_register_exit_code_test_'));
  tearDown(() => home.deleteSync(recursive: true));

  /// at_register run against the loopback registrar in [mode], with four
  /// verification codes on its stdin and [home] as its home directory.
  Future<({int exitCode, String stdout, String stderr})> runAtRegister(
      String mode) async {
    final process = await Process.start(Platform.resolvedExecutable,
        ['test/fixtures/at_register_against_loopback.dart', mode],
        environment: {'HOME': home.path});
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write('ABCD\n' * 4);
    await process.stdin.close();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 90),
        onTimeout: () {
      process.kill();
      return -1;
    });
    return (exitCode: exitCode, stdout: await stdout, stderr: await stderr);
  }

  test('An activation that fails after registration exits non-zero', () async {
    File('${home.path}/.atsign/keys/@registered_key.atKeys')
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');

    final run = await runAtRegister('hands-over-cram');

    expect(run.stderr, contains('Keys file already exists'),
        reason: 'the premise: the atSign was registered and the activation '
            'after it failed');
    expect(run.exitCode, 1, reason: 'at_activate exits 1 for the same failure');
    expect(run.stderr, isNot(contains('no command was given')),
        reason: 'at_register names the at_activate command it runs');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
