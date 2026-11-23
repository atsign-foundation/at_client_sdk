@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The package root, whether the test runner was started in the package or at
/// the repository root.
Directory _packageRoot() {
  for (final start in [
    Directory.current.absolute,
    Directory('${Directory.current.path}/packages/at_client_web').absolute,
  ]) {
    var dir = start;
    while (true) {
      if (File('${dir.path}/tool/build.sh').existsSync() &&
          File('${dir.path}/bridge-manifest.json').existsSync()) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  throw StateError('could not find the at_client_web package root');
}

/// A stub `dart` that records its argv and WASM_REQUIRED, writes the file a
/// `compile js` or `compile wasm` call is asked for (and the `.mjs` beside a
/// wasm module) unless told not to, and hands `tool/manifest.dart` to the real
/// Dart so the manifest bytes are the generator's own.
const _stubDart = r'''#!/usr/bin/env bash
echo "WASM_REQUIRED=${WASM_REQUIRED-unset} $*" >> "$STUB_LOG"
if [[ "$1" == tool/manifest.dart ]]; then
  shift
  exec "$REAL_DART" "$REAL_MANIFEST_SCRIPT" "$@"
fi
if [[ "$1" == compile ]]; then
  kind=$2
  out=
  while (( $# > 0 )); do
    if [[ "$1" == -o ]]; then out=$2; fi
    shift
  done
  if [[ "$kind" == js ]]; then
    [[ "${STUB_JS:-write}" == fail ]] && exit 1
    [[ "${STUB_JS:-write}" == write ]] && echo js > "$out"
  else
    [[ "${STUB_WASM:-write}" == fail ]] && exit 1
    echo wasm > "$out"
    echo mjs > "${out%.wasm}.mjs"
  fi
  exit 0
fi
exit 0
''';

class _Run {
  _Run(this.result, this.pkg, this.log);
  final ProcessResult result;
  final Directory pkg;
  final List<String> log;

  int get code => result.exitCode;
  String get stderrText => result.stderr as String;
  bool exists(String name) => File('${pkg.path}/build/$name').existsSync();
  List<String> get compiles =>
      log.where((l) => l.contains(' compile ')).toList();
}

late Directory _root;
late Directory _scratch;
var _counter = 0;

/// Runs a copy of tool/build.sh in a scratch package, with the stub first on
/// PATH. [seed] names files to create in build/ beforehand (stale outputs).
Future<_Run> _build(
  List<String> args, {
  Map<String, String> env = const {},
  List<String> seed = const [],
}) async {
  final dir = Directory('${_scratch.path}/run${_counter++}')
    ..createSync(recursive: true);
  final pkg = Directory('${dir.path}/pkg')..createSync();
  Directory('${pkg.path}/tool').createSync();
  File('${_root.path}/tool/build.sh').copySync('${pkg.path}/tool/build.sh');
  final bin = Directory('${dir.path}/bin')..createSync();
  final stub = File('${bin.path}/dart')..writeAsStringSync(_stubDart);
  await Process.run('chmod', ['+x', stub.path]);
  final log = File('${dir.path}/stub.log')..writeAsStringSync('');
  if (seed.isNotEmpty) {
    Directory('${pkg.path}/build').createSync();
    for (final name in seed) {
      File('${pkg.path}/build/$name').writeAsStringSync('stale');
    }
  }
  final environment = Map<String, String>.of(Platform.environment)
    ..remove('WASM_REQUIRED')
    ..['PATH'] = '${bin.path}:${Platform.environment['PATH']}'
    ..['STUB_LOG'] = log.path
    ..['REAL_DART'] = Platform.resolvedExecutable
    ..['REAL_MANIFEST_SCRIPT'] = '${_root.path}/tool/manifest.dart'
    ..addAll(env);
  final result = await Process.run(
    'bash',
    ['${pkg.path}/tool/build.sh', ...args],
    workingDirectory: dir.path,
    environment: environment,
  );
  return _Run(result, pkg, log.readAsLinesSync());
}

String _committedManifest() =>
    File('${_root.path}/bridge-manifest.json').readAsStringSync();

void main() {
  setUpAll(() {
    _root = _packageRoot();
    _scratch = Directory('${_root.path}/.dart_tool/build_script_test')
      ..createSync(recursive: true);
  });
  tearDownAll(() {
    if (_scratch.existsSync()) _scratch.deleteSync(recursive: true);
  });

  test('dart2js target builds only the js file', () async {
    for (final form in [
      ['--target', 'dart2js'],
      ['--target=dart2js'],
    ]) {
      final run = await _build(
        ['at_client_bridge_entry', ...form],
        seed: ['at_client_web.wasm', 'at_client_web.mjs'],
      );
      expect(run.code, 0, reason: '$form: ${run.stderrText}');
      expect(run.exists('at_client_web.js'), isTrue, reason: '$form');
      expect(run.exists('at_client_web.wasm'), isFalse, reason: '$form');
      expect(run.exists('at_client_web.mjs'), isFalse, reason: '$form');
      expect(run.compiles, hasLength(1), reason: '$form');
      expect(run.compiles.single, contains(' compile js '));
    }
  });

  test('dart2wasm target builds the wasm module and its loader', () async {
    final run = await _build(
      ['at_client_bridge_entry', '--target', 'dart2wasm'],
      seed: ['at_client_web.js'],
    );
    expect(run.code, 0, reason: run.stderrText);
    expect(run.exists('at_client_web.wasm'), isTrue);
    expect(run.exists('at_client_web.mjs'), isTrue);
    expect(run.exists('at_client_web.js'), isFalse);
    expect(run.exists('bridge-manifest.json'), isTrue);
    expect(run.compiles.single, contains(' compile wasm '));
  });

  test('dart2wasm target forces WASM_REQUIRED on', () async {
    for (final env in [
      <String, String>{},
      {'WASM_REQUIRED': '0'},
    ]) {
      final run = await _build(
        ['at_client_bridge_entry', '--target', 'dart2wasm'],
        env: env,
      );
      expect(run.code, 0, reason: '$env: ${run.stderrText}');
      expect(run.compiles.single, startsWith('WASM_REQUIRED=1 '),
          reason: '$env');
    }
  });

  test('A dart2wasm compile failure exits 1 for the wasm target', () async {
    for (final env in [
      {'STUB_WASM': 'fail'},
      {'STUB_WASM': 'fail', 'WASM_REQUIRED': '0'},
    ]) {
      final run = await _build(
        ['at_client_bridge_entry', '--target', 'dart2wasm'],
        env: env,
      );
      expect(run.code, 1, reason: '$env');
      expect(run.stderrText, contains('dart2wasm compile failed'));
    }
  });

  test('A dart2js build is untouched by a failing dart2wasm', () async {
    final run = await _build(
      ['at_client_bridge_entry', '--target', 'dart2js'],
      env: {'STUB_WASM': 'fail'},
    );
    expect(run.code, 0, reason: run.stderrText);
    expect(run.exists('at_client_web.js'), isTrue);
    expect(run.compiles.any((l) => l.contains(' compile wasm ')), isFalse);
  });

  test('No arguments keeps both entries and a best-effort dart2wasm', () async {
    final failing = await _build([], env: {'STUB_WASM': 'fail'});
    expect(failing.code, 0, reason: failing.stderrText);
    expect(
      RegExp('warning: dart2wasm compile failed')
          .allMatches(failing.stderrText),
      hasLength(2),
    );
    expect(failing.exists('at_client.js'), isTrue);
    expect(failing.exists('at_client_web.js'), isTrue);

    final working = await _build([]);
    expect(working.code, 0, reason: working.stderrText);
    for (final name in [
      'at_client.js',
      'at_client.wasm',
      'at_client.mjs',
      'at_client_web.js',
      'at_client_web.wasm',
      'at_client_web.mjs',
    ]) {
      expect(working.exists(name), isTrue, reason: name);
    }
  });

  test('Bad build arguments are refused naming the allowed values', () async {
    for (final args in [
      ['--target', 'both'],
      ['--target='],
      ['--target', 'dart2wasm_x'],
      ['at_client_not_an_entry'],
      ['at_client_bridge_entry', '--target', 'both'],
    ]) {
      final run = await _build(args);
      expect(run.code, isNot(0), reason: '$args');
      expect(run.stderrText, contains('dart2js'), reason: '$args');
      expect(run.stderrText, contains('dart2wasm'), reason: '$args');
      expect(run.compiles, isEmpty, reason: '$args');
    }
    final entry = await _build(['at_client_not_an_entry']);
    expect(entry.stderrText, contains('at_client_bridge_entry'));
  });

  test('A build removes stale js wasm and mjs files of the entry', () async {
    final run = await _build(
      ['at_client_bridge_entry', '--target', 'dart2js'],
      seed: ['at_client_web.js', 'at_client_web.wasm', 'at_client_web.mjs'],
      env: {'STUB_JS': 'skip'},
    );
    expect(run.code, 0, reason: run.stderrText);
    expect(run.exists('at_client_web.js'), isFalse);
    expect(run.exists('at_client_web.wasm'), isFalse);
    expect(run.exists('at_client_web.mjs'), isFalse);
  });

  test('Both targets write the committed manifest bytes', () async {
    for (final target in ['dart2js', 'dart2wasm']) {
      final run = await _build(['at_client_bridge_entry', '--target', target]);
      expect(run.code, 0, reason: '$target: ${run.stderrText}');
      final built =
          File('${run.pkg.path}/build/bridge-manifest.json').readAsStringSync();
      expect(built, _committedManifest(), reason: target);
      final manifestAt = run.log.indexWhere((l) => l.contains('manifest.dart'));
      final compileAt = run.log.indexWhere((l) => l.contains(' compile '));
      expect(manifestAt, isNonNegative);
      expect(manifestAt, lessThan(compileAt),
          reason: 'manifest before compile');
    }
  });
}
