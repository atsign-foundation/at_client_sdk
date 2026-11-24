@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// tool/build.sh picks its targets from its argument. A stub `dart` first on
/// PATH records each invocation, so no compile runs.
void main() {
  late Directory stubDir;
  late File calls;

  setUp(() {
    stubDir = Directory.systemTemp.createTempSync('at_client_web_build_');
    addTearDown(() => stubDir.deleteSync(recursive: true));
    calls = File('${stubDir.path}/calls');
    final stub = File('${stubDir.path}/dart')
      ..writeAsStringSync('#!/usr/bin/env bash\n'
          'echo "\$*" >> "${calls.path}"\n');
    Process.runSync('chmod', ['+x', stub.path]);
  });

  Future<ProcessResult> build(List<String> args) => Process.run('bash', [
        'tool/build.sh',
        ...args
      ], environment: {
        'PATH': '${stubDir.path}:${Platform.environment['PATH']}',
      });

  List<String> recorded() =>
      calls.existsSync() ? calls.readAsLinesSync() : <String>[];

  test('build.sh with no argument builds both entries', () async {
    final result = await build([]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(recorded(), [
      'compile js -O2 --no-minify web/at_client_web_entry.dart -o build/at_client.js',
      'compile wasm -O2 --no-minify web/at_client_web_entry.dart -o build/at_client.wasm',
      'compile js -O2 --no-minify web/at_client_bridge_entry.dart -o build/at_client_web.js',
      'compile wasm -O2 --no-minify web/at_client_bridge_entry.dart -o build/at_client_web.wasm',
    ]);
  });

  test(
      'build.sh with at_client_bridge_entry builds only the bridge with dart2js',
      () async {
    final result = await build(['at_client_bridge_entry']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(recorded(), [
      'compile js -O2 --no-minify web/at_client_bridge_entry.dart -o build/at_client_web.js',
    ]);
  });

  test('build.sh with any other argument is refused', () async {
    final result = await build(['bogus']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains("unknown entry 'bogus'"));
    expect(recorded(), isEmpty);
  });
}
