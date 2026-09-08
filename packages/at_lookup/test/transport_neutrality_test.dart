import 'dart:io';

import 'package:test/test.dart';

/// `dart compile wasm` accepts `dart:io` and stubs it, so nothing in the
/// toolchain fails when a native import lands in a library that claims to be
/// web-safe. This walks the source instead. The `wasm_gates.yaml` stanza does
/// it across the whole import graph, including the packages `at_lookup.dart`
/// pulls in; until at_lookup has one, this covers at_lookup's own sources.
void main() {
  /// The `dart:` libraries that resolve on every platform. `dart:io` and
  /// `dart:ffi` are absent by construction; so are the web-only ones, because a
  /// file outside `lib/src/io` has to compile both ways.
  const platformNeutral = {
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:core',
    'dart:developer',
    'dart:math',
    'dart:typed_data',
  };

  test('lib/src outside io reaches only platform-neutral libraries', () {
    final sources = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('.dart') &&
            !file.path.contains('${Platform.pathSeparator}io'
                '${Platform.pathSeparator}'))
        .toList();

    expect(sources, isNotEmpty,
        reason: 'lib/src holds no neutral Dart sources — either the package '
            'has moved, or this suite is not running from the at_lookup '
            'package root');

    final pattern = RegExp('''^\\s*(?:import|export)\\s+['"](dart:[a-z_]+)''');
    final offenders = [
      for (final file in sources)
        for (final line in file.readAsLinesSync())
          if (pattern.firstMatch(line) case final match?
              when !platformNeutral.contains(match.group(1)))
            '${file.path}: ${match.group(1)}',
    ];

    expect(offenders, isEmpty);
  });
}
