@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The slim client, with `InMemoryAtClientStorage` and its at_persistence
/// import chain, compiles for both browser targets.
void main() {
  const entry = 'web/at_client_wasm_entry.dart';

  for (final (target, output) in [('js', 'out.js'), ('wasm', 'out.wasm')]) {
    test('compiles under dart2$target', () async {
      final dir = Directory.systemTemp.createTempSync('at_client_wasm_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final result = await Process.run(Platform.resolvedExecutable,
          ['compile', target, entry, '-o', '${dir.path}/$output']);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }, timeout: Timeout(Duration(minutes: 5)));
  }
}
