import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Catalogue: features/at_lookup/transports.feature
///
/// The walk follows every package the barrels import, taking each
/// conditional import's default branch. That the barrels also compile with
/// dart2wasm is the wasm gate's compile probe.
void main() {
  test('The default barrels reach no platform library', () async {
    for (final barrel in ['at_lookup.dart', 'at_lookup_web.dart']) {
      final reached = await _reach('package:at_lookup/$barrel');

      expect(reached.libraries.intersection({'dart:io', 'dart:ffi'}), isEmpty,
          reason: '$barrel reaches no dart:io, directly or through another '
              'package');
      expect(reached.files.where((f) => !f.contains('/at_lookup/')),
          isNotEmpty,
          reason: 'the control: the walk left at_lookup for the packages '
              '$barrel imports');
    }
    expect((await _reach('package:at_lookup/at_lookup_io.dart')).libraries,
        contains('dart:io'),
        reason: 'the control: the io barrel holds what the default ones '
            'leave out');
  });
}

/// The `dart:` libraries and the files [entry] reaches through `import`,
/// `export` and `part`, across packages, taking each conditional import's
/// default branch.
Future<({Set<String> libraries, Set<String> files})> _reach(
    String entry) async {
  final libraries = <String>{};
  final files = <String>{};
  final pending = [Uri.parse(entry)];
  final directive = RegExp(r'''^(?:import|export|part)\s+['"]([^'"]+)['"]''',
      multiLine: true);
  while (pending.isNotEmpty) {
    final uri = pending.removeLast();
    final resolved = uri.scheme == 'package'
        ? await Isolate.resolvePackageUri(uri)
        : uri;
    if (resolved == null || !files.add(resolved.toFilePath())) continue;
    final source = File(resolved.toFilePath()).readAsStringSync();
    for (final match in directive.allMatches(source)) {
      final target = Uri.parse(match[1]!);
      if (target.scheme == 'dart') {
        libraries.add('$target');
      } else {
        pending.add(target.hasScheme ? target : uri.resolveUri(target));
      }
    }
  }
  return (libraries: libraries, files: files);
}
