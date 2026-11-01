import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Catalogue: features/at_client/web_safe.feature
///
/// The walk follows every package a library imports, taking each conditional
/// import's branch as a dart2wasm build does, or as the VM does for the
/// controls. That at_client.dart and memory.dart compile with dart2wasm is
/// also the wasm gate's compile probe.
void main() {
  const platform = {'dart:io', 'dart:ffi'};

  test('at_client.dart reaches no platform library', () async {
    for (final barrel in ['at_client.dart', 'memory.dart']) {
      final reached = await _reach(Uri.parse('package:at_client/$barrel'));

      expect(reached.libraries.intersection(platform), isEmpty,
          reason: '$barrel reaches no dart:io, directly or through another '
              'package');
      expect(reached.files.where((f) => f.contains('/at_lookup/')), isNotEmpty,
          reason: 'the control: the walk left at_client for the packages '
              '$barrel imports');
    }
    expect(
        (await _reach(Uri.parse('package:at_client/at_client_io.dart')))
            .libraries,
        contains('dart:io'),
        reason: 'the control: the io barrel holds what at_client.dart leaves '
            'out');
    expect(
        (await _reach(Uri.parse('package:at_client/at_client.dart'),
                environment: _vm))
            .libraries,
        contains('dart:ffi'),
        reason: 'the control: on the VM the crypto backends take the native '
            'branch the browser build leaves out');
  });

  test('A web program can build a client on the memory storage', () async {
    const program = 'test/web/web_memory_client.dart';
    final out = Directory.systemTemp.createTempSync('at_client_web_safe');
    addTearDown(() => out.deleteSync(recursive: true));

    final compiled = await Process.run(Platform.resolvedExecutable,
        ['compile', 'wasm', program, '-o', '${out.path}/program.wasm']);

    expect(compiled.exitCode, 0,
        reason: 'dart2wasm compiles it:\n${compiled.stdout}${compiled.stderr}');
    final reached = await _reach(File(program).absolute.uri);
    expect(reached.libraries.intersection(platform), isEmpty,
        reason: 'nothing the program reaches imports dart:io');
    expect(
        reached.files.where((f) => f.contains('/at_client/lib/')), isNotEmpty,
        reason: 'the control: the walk reached at_client from the program');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// How `if (dart.library.x)` evaluates in a dart2wasm build.
const _wasm = {
  'dart.library.io': false,
  'dart.library.ffi': false,
  'dart.library.html': false,
  'dart.library.js': false,
  'dart.library.js_interop': true,
  'dart.library.js_util': true,
};

/// How `if (dart.library.x)` evaluates on the VM.
const _vm = {
  'dart.library.io': true,
  'dart.library.ffi': true,
  'dart.library.html': false,
  'dart.library.js': false,
  'dart.library.js_interop': false,
  'dart.library.js_util': false,
};

/// The `dart:` libraries and the files [entry] reaches through `import`,
/// `export` and `part`, across packages, each conditional import resolved
/// under [environment].
Future<({Set<String> libraries, Set<String> files})> _reach(Uri entry,
    {Map<String, bool> environment = _wasm}) async {
  final libraries = <String>{};
  final files = <String>{};
  final pending = [entry];
  final directive = RegExp(
      r'''^(?:import|export|part)\s+['"]([^'"]+)['"]((?:\s+if\s*\(\s*[\w.]+\s*\)\s*['"][^'"]+['"])*)''',
      multiLine: true);
  final conditional = RegExp(r'''if\s*\(\s*([\w.]+)\s*\)\s*['"]([^'"]+)['"]''');
  while (pending.isNotEmpty) {
    final uri = pending.removeLast();
    final resolved =
        uri.scheme == 'package' ? await Isolate.resolvePackageUri(uri) : uri;
    if (resolved == null || !files.add(resolved.toFilePath())) continue;
    final source = File(resolved.toFilePath()).readAsStringSync();
    for (final match in directive.allMatches(source)) {
      var chosen = match[1]!;
      for (final branch in conditional.allMatches(match[2]!)) {
        if (environment[branch[1]] == true) {
          chosen = branch[2]!;
          break;
        }
      }
      final target = Uri.parse(chosen);
      if (target.scheme == 'dart') {
        libraries.add('$target');
      } else {
        pending.add(target.hasScheme ? target : resolved.resolveUri(target));
      }
    }
  }
  return (libraries: libraries, files: files);
}
