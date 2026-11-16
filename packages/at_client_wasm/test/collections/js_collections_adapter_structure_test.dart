@TestOn('vm')
library;

// Scenarios: features/at_client_wasm/js_collections_adapter.feature. Each
// test is named after its scenario. VM-only: it reads the package sources.

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

final _directive = RegExp(r'''^\s*(?:export|part)\s+[^;]*;''', multiLine: true);
final _quotedUri = RegExp(r'''['"]([^'"]+)['"]''');

/// The files [entry] re-exports or includes, directly or through other
/// files of [libDir]: every quoted URI of every `export` and `part`
/// directive (single or double quoted, conditional branches included) is
/// followed, and
/// a `package:at_client_wasm/` URI is resolved inside [libDir].
Set<String> _exportGraph(File entry, Directory libDir) {
  final seen = <String>{};
  final pending = [entry.absolute.path];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final directive in _directive.allMatches(file.readAsStringSync())) {
      for (final uri in _quotedUri.allMatches(directive.group(0)!)) {
        final target = uri.group(1)!;
        if (target.startsWith('package:at_client_wasm/')) {
          pending.add(libDir.uri
              .resolve(target.substring('package:at_client_wasm/'.length))
              .toFilePath());
        } else if (!target.contains(':')) {
          pending.add(file.parent.uri.resolve(target).toFilePath());
        }
      }
    }
  }
  return seen;
}

/// The top-level libraries of [libDir] that reach [target] through exports
/// and parts.
List<String> _librariesReaching(Directory libDir, String target) => [
      for (final library in libDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (_exportGraph(library, libDir).contains(target)) library.path
    ];

void main() {
  group('structure', () {
    test('The adapter is not exported and reaches no web-only API', () async {
      final adapter = await Isolate.resolvePackageUri(Uri.parse(
          'package:at_client_wasm/src/collections/js_collections_adapter.dart'));
      expect(adapter, isNotNull);
      final libDir = Directory.fromUri(adapter!.resolve('../../'));

      expect(libDir.listSync().whereType<File>(), isNotEmpty);
      expect(_librariesReaching(libDir, adapter.toFilePath()), isEmpty);

      final visited = <String>{};
      final pending = [adapter.toFilePath()];
      final importPattern =
          RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true);
      while (pending.isNotEmpty) {
        final path = pending.removeLast();
        if (!visited.add(path)) continue;
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('dart:js_interop')), reason: path);
        expect(source, isNot(contains('package:web')), reason: path);
        for (final match in importPattern.allMatches(source)) {
          final target = match.group(1)!;
          if (target.startsWith('package:at_client_wasm/')) {
            pending.add(libDir.uri
                .resolve(target.substring('package:at_client_wasm/'.length))
                .toFilePath());
          } else if (!target.contains(':')) {
            pending.add(File(path).parent.uri.resolve(target).toFilePath());
          }
        }
      }
      expect(visited, contains(adapter.toFilePath()));
    });

    group('the export check', () {
      late Directory lib;

      setUp(() {
        lib = Directory.systemTemp.createTempSync('export_graph_');
        Directory('${lib.path}/src/a').createSync(recursive: true);
        File('${lib.path}/src/a/adapter.dart').writeAsStringSync('class A {}');
      });

      tearDown(() => lib.deleteSync(recursive: true));

      String adapter() => '${lib.path}/src/a/adapter.dart';

      test('A transitive re-export through lib/src is found', () {
        File('${lib.path}/src/mid.dart')
            .writeAsStringSync("export 'a/adapter.dart';");
        File('${lib.path}/top.dart')
            .writeAsStringSync("export 'src/mid.dart' show A;");

        expect(_librariesReaching(lib, adapter()), ['${lib.path}/top.dart']);
      });

      test('A re-export by package URI and a part are found', () {
        File('${lib.path}/src/mid.dart')
            .writeAsStringSync("part 'a/adapter.dart';");
        File('${lib.path}/top.dart')
            .writeAsStringSync("export 'package:at_client_wasm/src/mid.dart';");

        expect(_librariesReaching(lib, adapter()), ['${lib.path}/top.dart']);
      });

      test('A conditional export reaches the adapter through its branch', () {
        File('${lib.path}/src/mid.dart')
            .writeAsStringSync("export 'a/adapter.dart';");
        File('${lib.path}/src/stub.dart').writeAsStringSync('class S {}');
        File('${lib.path}/top.dart').writeAsStringSync(
            "export 'src/stub.dart' if (dart.library.js_interop) 'src/mid.dart';");

        expect(_librariesReaching(lib, adapter()), ['${lib.path}/top.dart']);
      });

      test('A double-quoted export is found', () {
        File('${lib.path}/top.dart')
            .writeAsStringSync('export "src/a/adapter.dart";');

        expect(_librariesReaching(lib, adapter()), ['${lib.path}/top.dart']);
      });

      test('An import, or a library that reaches nothing, is not a re-export',
          () {
        File('${lib.path}/top.dart')
            .writeAsStringSync("import 'src/a/adapter.dart';");
        File('${lib.path}/other.dart').writeAsStringSync("export 'dart:io';");

        expect(_librariesReaching(lib, adapter()), isEmpty);
      });
    });

    test('The adapter names error kinds without runtimeType', () async {
      final adapter = await Isolate.resolvePackageUri(Uri.parse(
          'package:at_client_wasm/src/collections/js_collections_adapter.dart'));
      expect(File.fromUri(adapter!).readAsStringSync(),
          isNot(contains('runtimeType')));
    });
  });
}
