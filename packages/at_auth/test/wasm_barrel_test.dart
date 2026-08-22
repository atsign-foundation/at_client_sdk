import 'dart:io';

import 'package:test/test.dart';

/// `package:at_auth/at_auth.dart` must stay compilable for a WASM target,
/// which `dart2wasm` refuses if `dart:io` is reachable from the entry point.
///
/// This walks at_auth's OWN sources from that barrel and fails if any of them
/// imports `dart:io`. It deliberately stops at the package boundary: at_auth
/// still reaches `dart:io` transitively through at_lookup and at_chops, and
/// splitting those is separate work. So this proves at_auth has done its half,
/// not that the result compiles to WASM today.
void main() {
  final libDir = Directory('lib');

  /// Every at_auth file reachable from [entry] by import or export.
  Set<String> reachableFrom(String entry) {
    final seen = <String>{};
    final queue = <String>[entry];
    while (queue.isNotEmpty) {
      final path = queue.removeLast();
      if (!seen.add(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      // Whole file, not line by line: a conditional import is often wrapped
      // across two lines, and the rule below must not depend on that. Only a
      // path directly preceded by `import`/`export` counts, so for
      // `export 'a.dart' if (dart.library.io) 'b.dart';` this contributes
      // `a.dart` and NOT `b.dart` — the branch dart2wasm takes. Pinned below.
      for (final m in RegExp(r'''(?:import|export)\s+'([^']+)''')
          .allMatches(file.readAsStringSync())) {
        final target = m.group(1)!;
        String? resolved;
        if (target.startsWith('package:at_auth/')) {
          resolved = 'lib/${target.substring('package:at_auth/'.length)}';
        } else if (!target.contains(':')) {
          resolved = File('${File(path).parent.path}/$target')
              .uri
              .normalizePath()
              .toFilePath();
          resolved = resolved.replaceFirst('${Directory.current.path}/', '');
        }
        if (resolved != null) queue.add(resolved);
      }
    }
    return seen;
  }

  /// The `dart:io` importers among [files].
  List<String> ioImporters(Set<String> files) => [
        for (final path in files)
          if (File(path).existsSync() &&
              File(path).readAsLinesSync().any(
                  (l) => RegExp(r"""^\s*import\s+'dart:io'""").hasMatch(l)))
            path
      ]..sort();

  test('the main barrel reaches no dart:io in at_auth s own sources', () {
    final reachable = reachableFrom('lib/at_auth.dart');

    // Positive control: the walk really traversed, rather than returning the
    // entry file alone and reporting a vacuous pass.
    expect(reachable, contains('lib/src/at_auth_impl.dart'),
        reason: 'the import walk did not reach at_auth_impl.dart, so a clean '
            'result below would say nothing');
    expect(reachable.length, greaterThan(20),
        reason: 'only ${reachable.length} files reached - the walk is broken');

    expect(ioImporters(reachable), isEmpty,
        reason: 'these are reachable from at_auth.dart and import dart:io, so '
            'a WASM build of the core fails. They belong behind '
            'at_auth_io.dart');
  });

  test('the io barrel is where dart:io lives', () {
    final io = ioImporters(reachableFrom('lib/at_auth_io.dart'));

    // Negative control for the check above: the same probe on the io barrel
    // must find something, or `isEmpty` there proves only that it never looks.
    expect(io, isNotEmpty,
        reason: 'at_auth_io.dart should reach dart:io - if it does not, the '
            'detector is broken and the main-barrel test is vacuous');
    expect(io, contains('lib/src/keys/io/file_io.dart'));
  });

  test('a conditional import contributes only its default branch', () {
    final reachable = reachableFrom('lib/at_auth.dart');

    // Both halves matter. The first proves the conditional-import line was
    // parsed at all; without it the second passes just as well when the walker
    // silently skipped the line and saw neither branch.
    expect(reachable, contains('lib/src/auth/probe_default_web.dart'),
        reason: 'the default (non-dart:io) branch should be reached');
    expect(reachable, isNot(contains('lib/src/auth/probe_default_io.dart')),
        reason: 'the dart:io branch is never taken by dart2wasm, so counting '
            'it would fail this suite over code a WASM build excludes');
  });

  test('libDir sanity', () => expect(libDir.existsSync(), isTrue));
}
