@TestOn('vm')
library;

// Scenarios: features/at_client_wasm/js_collections_adapter.feature. Each
// test is named after its scenario. VM-only: it reads the package sources.

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  group('structure', () {
    test('The adapter is not exported and reaches no web-only API', () async {
      final adapter = await Isolate.resolvePackageUri(Uri.parse(
          'package:at_client_wasm/src/collections/js_collections_adapter.dart'));
      expect(adapter, isNotNull);
      final libDir = adapter!.resolve('../../');

      final topLevel = Directory.fromUri(libDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(topLevel, isNotEmpty);
      for (final library in topLevel) {
        expect(library.readAsStringSync(), isNot(contains('collections/')),
            reason: library.path);
      }

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
            pending.add(libDir
                .resolve(target.substring('package:at_client_wasm/'.length))
                .toFilePath());
          } else if (!target.contains(':')) {
            pending.add(File(path).parent.uri.resolve(target).toFilePath());
          }
        }
      }
      expect(visited, contains(adapter.toFilePath()));
    });
  });
}
