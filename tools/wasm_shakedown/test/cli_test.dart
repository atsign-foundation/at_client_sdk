// Exercises the real entry point, so VM only like the rest.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

void main() {
  final toolRoot = Directory.current;
  final bin = '${toolRoot.path}/bin/wasm_shakedown.dart';

  Future<ProcessResult> run(List<String> args, {String? workingDirectory}) =>
      Process.run(Platform.resolvedExecutable, args,
          workingDirectory: workingDirectory ?? toolRoot.path);

  test('rejects an option-looking package value with a useful message',
      () async {
    final result = await run(
        ['run', 'wasm_shakedown', '--package', '--config', 'gates.yaml']);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('--package needs a package name'));
    expect(result.stderr, isNot(contains('unrecognised argument')));
  });

  test('missing package_config is reported as a clean usage error', () async {
    final temp = Directory.systemTemp.createTempSync('wasm_shakedown_cli_');
    addTearDown(() => temp.deleteSync(recursive: true));

    final result = await run(
      ['--packages=${packageConfigFile().path}', bin],
      workingDirectory: temp.path,
    );

    expect(result.exitCode, 2);
    expect(result.stderr, contains('run `dart pub get` first'));
    expect(result.stderr, isNot(contains('Unhandled exception')));
  });

  test('package narrowing scopes barrel validation and marks failed ratchets',
      () async {
    final temp = Directory.systemTemp.createTempSync('wasm_shakedown_cli_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final config = File('${temp.path}/gates.yaml')..writeAsStringSync('''
at_chops:
  ratchets:
    - barrel: package:at_chops/at_chops.dart
      allowed_offenders: []
      max_blocked_packages: 2
      min_files_walked: 999999
  probe:
    - package:at_chops/at_chops.dart
  controls:
    - barrel: package:at_chops/at_chops_ffi.dart
      reaches_library: dart:ffi
      because: the FFI algorithms it exists to quarantine

at_auth:
  ratchets:
    - barrel: package:at_auth/renamed.dart
      allowed_offenders: []
      max_blocked_packages: 4
      min_files_walked: 850
  probe:
    - package:at_auth/at_auth.dart
''');

    final result = await run([
      'run',
      'wasm_shakedown',
      '--config',
      config.path,
      '--package',
      'at_chops',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, isNot(contains('renamed.dart')));
    expect(result.stdout, contains('ratchet'));
    expect(result.stdout, contains('FAILED'));
  });
}
