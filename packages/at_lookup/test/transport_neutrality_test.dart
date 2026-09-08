import 'dart:io';

import 'package:test/test.dart';

/// `dart compile wasm` accepts `dart:io` and stubs it, so nothing in the
/// toolchain fails when a native import lands in a library that claims to be
/// web-safe. This walks the source instead. The `wasm_gates.yaml` stanza does
/// it across the whole import graph; until at_lookup has one, this covers the
/// directory the seam lives in.
void main() {
  const allowed = {'dart:async'};

  test('lib/src/transport imports no platform library', () {
    final directory = Directory('lib/src/transport');
    expect(directory.existsSync(), isTrue,
        reason: 'run this from the at_lookup package root');

    final pattern = RegExp('''^\\s*(?:import|export)\\s+['"](dart:[a-z_]+)''');
    final offenders = [
      for (final file in directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')))
        for (final line in file.readAsLinesSync())
          if (pattern.firstMatch(line) case final match?
              when !allowed.contains(match.group(1)))
            '${file.path}: ${match.group(1)}',
    ];

    expect(offenders, isEmpty);
  });
}
