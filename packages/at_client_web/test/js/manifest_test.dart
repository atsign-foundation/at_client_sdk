@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_client_web/src/js/bridge_surface.dart' show bridgeSurface;
import 'package:test/test.dart';

/// The package root, whether the test runner was started in the package or
/// at the repository root.
Directory _packageRoot() {
  final starts = [
    Directory.current.absolute,
    Directory('${Directory.current.path}/packages/at_client_web').absolute,
  ];
  for (final start in starts) {
    var dir = start;
    while (true) {
      if (File('${dir.path}/tool/manifest.dart').existsSync() &&
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

/// Runs the generator from [root], capturing stdout as bytes so a BOM or a
/// missing trailing newline cannot be normalised away.
ProcessResult _runManifest(Directory root, List<String> args,
        {Map<String, String>? environment}) =>
    Process.runSync(
      Platform.resolvedExecutable,
      ['tool/manifest.dart', ...args],
      workingDirectory: root.path,
      environment: environment,
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );

List<int> _stdout(ProcessResult result) => result.stdout as List<int>;

void main() {
  final root = _packageRoot();
  final committed = File('${root.path}/bridge-manifest.json').readAsBytesSync();

  test('the generator reproduces the committed manifest byte for byte', () {
    final run = _runManifest(root, const []);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(_stdout(run), equals(committed));
  });

  test('--out writes the same bytes atomically', () {
    final scratch = Directory('${root.path}/.dart_tool')
      ..createSync(recursive: true);
    final temp = scratch.createTempSync('manifest_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = '${temp.path}/bridge-manifest.json';
    final run = _runManifest(root, ['--out', path]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect(_stdout(run), isEmpty, reason: '--out writes nothing to stdout');
    expect(File(path).readAsBytesSync(), equals(committed));
    expect(File('$path.tmp').existsSync(), isFalse,
        reason: 'the temporary file was renamed away');
  });

  test('any other argument is refused, naming both forms', () {
    final run = _runManifest(root, ['--target', 'dart2js']);
    expect(run.exitCode, 1);
    expect(run.stderr as String, contains('dart tool/manifest.dart'));
    expect(run.stderr as String, contains('--out PATH'));
    expect(_stdout(run), isEmpty);
  });

  test('the TARGET environment does not change the bytes', () {
    final js = _runManifest(root, const [], environment: {'TARGET': 'dart2js'});
    final wasm =
        _runManifest(root, const [], environment: {'TARGET': 'dart2wasm'});
    expect(js.exitCode, 0, reason: '${js.stderr}');
    expect(wasm.exitCode, 0, reason: '${wasm.stderr}');
    expect(_stdout(js), equals(_stdout(wasm)));
    final source = File('${root.path}/tool/manifest.dart').readAsStringSync();
    expect(source, isNot(contains('Platform.environment')));
    expect(source, isNot(contains('fromEnvironment')));
    expect(source, isNot(contains("js/bridge.dart'")));
  });

  test('the shape is exact, with sorted members and one trailing LF', () {
    final bytes = committed;
    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, bytes.length >= 3 ? 3 : bytes.length),
        isNot([0xEF, 0xBB, 0xBF]),
        reason: 'no UTF-8 BOM');
    expect(bytes.last, 0x0A, reason: 'one trailing LF');
    expect(bytes.length < 2 || bytes[bytes.length - 2] != 0x0A, isTrue,
        reason: 'exactly one trailing LF');

    final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(manifest.keys.toList(), [
      'collectionErrorCodes',
      'errorCodes',
      'schemaVersion',
      'surface',
    ]);
    expect(manifest['schemaVersion'], 1);

    for (final key in ['collectionErrorCodes', 'errorCodes']) {
      final values = (manifest[key] as List<dynamic>).cast<String>().toList();
      _expectSortedUnique(values, key);
    }

    final surface = manifest['surface'] as Map<String, dynamic>;
    expect(surface.keys.toList(), [...surface.keys]..sort());
    for (final MapEntry(:key, :value) in surface.entries) {
      _expectSortedUnique(
          (value as List<dynamic>).cast<String>().toList(), 'surface[$key]');
    }
  });

  test('build.sh runs the generator once, for every entry', () {
    final source = File('${root.path}/tool/build.sh').readAsStringSync();
    const invocation =
        'dart tool/manifest.dart --out "\$out/bridge-manifest.json"';
    expect(invocation.allMatches(source), hasLength(1),
        reason: 'the generator is invoked exactly once');
    final mkdir = source.indexOf('mkdir -p "\$out"');
    final call = source.indexOf(invocation);
    final branch = source.indexOf('case "\${1:-}"');
    expect(mkdir, isNonNegative);
    expect(call, greaterThan(mkdir),
        reason: 'the output directory exists first');
    expect(call, lessThan(branch),
        reason: 'the call is outside the entry branches');
    final line = source.split('\n').firstWhere((l) => l.contains(invocation));
    expect(line, startsWith(invocation),
        reason: 'the call is unindented, so no conditional guards it');
    expect(source, contains('out=build'));
  });

  test('bridgeSurface is exactly the public members of every @JSExport class',
      () {
    final source =
        File('${root.path}/lib/src/js/bridge.dart').readAsStringSync();
    final scanned = _exportedSurface(source);
    expect(scanned.keys, isNotEmpty);
    expect(scanned, bridgeSurface,
        reason: 'a new exported member or a stale const entry fails here');
  });
}

/// `{class: sorted public members}` for each `@JSExport` class in [source]:
/// the two-space-indented declarations with a return type and a public name.
/// Constructors, fields and private members do not match.
Map<String, List<String>> _exportedSurface(String source) {
  final lines = source.split('\n');
  final member = RegExp(r'^  (?:static\s+)?[A-Za-z][\w<>?,. ]*\s([a-z]\w*)\(');
  final surface = <String, List<String>>{};
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] != '@JSExport()') continue;
    final name = RegExp(r'^class (\w+)').firstMatch(lines[i + 1])?.group(1);
    if (name == null) fail('@JSExport() on line ${i + 1} is not on a class');
    final members = <String>[];
    for (var k = i + 2; k < lines.length && lines[k] != '}'; k++) {
      final m = member.firstMatch(lines[k]);
      if (m != null) members.add(m.group(1)!);
    }
    surface[name] = members..sort();
  }
  return surface;
}

void _expectSortedUnique(List<String> values, String name) {
  expect(values, isNotEmpty, reason: '$name is non-empty');
  expect(values, equals([...values]..sort()), reason: '$name is sorted');
  expect(values.toSet(), hasLength(values.length),
      reason: '$name is duplicate-free');
}
