/// The shared shape of a per-package dependency-tree ratchet.
///
/// Each neutral package's `test/wasm/dep_tree_test.dart` supplies its barrels and
/// its baselines; the assertions, the two-way semantics and the failure messages
/// live here so that five copies cannot drift into five slightly different
/// notions of what the gate promises.
///
/// ```dart
/// void main() {
///   ratchetGroup(
///     'package:at_lookup/at_lookup.dart',
///     package: 'at_lookup',
///     expectedOffenders: const <String, List<String>>{...},
///     expectedBlocked: const <String>{...},
///     minFilesWalked: 600,
///   );
/// }
/// ```
library;

import 'package:test/test.dart';

import 'wasm_shakedown.dart';

/// Pins the platform libraries reachable from [barrel].
///
/// [expectedOffenders] is [package]'s own offending sources, keyed by
/// package-relative path; [expectedBlocked] is every package owning an offender
/// anywhere in the graph, [package] included. Both are asserted by **equality**,
/// which is what makes this a ratchet rather than a ceiling: a new entry means
/// someone introduced a browser-hostile import, a missing entry means a blocker
/// was fixed and the baseline owes an update. Both directions fail, and both are
/// meant to.
///
/// [minFilesWalked] guards the whole thing. Every assertion here is about what
/// the walk did *not* find, and a traversal that stalled at the entry point also
/// finds nothing — so set it near the real figure the baseline was taken at, not
/// to 1.
void ratchetGroup(
  String barrel, {
  required String package,
  required Map<String, List<String>> expectedOffenders,
  required Set<String> expectedBlocked,
  required int minFilesWalked,
  Map<String, bool> environment = webEnvironment,
}) {
  group(barrel, () {
    late Shakedown result;

    setUpAll(() => result = shakedown(barrel, environment: environment));

    test('$package owns exactly the offenders it is baselined for', () {
      expect(result.offendersIn(package), expectedOffenders,
          reason: _drift(barrel, result));
    });

    test('the blocked-package set is unchanged', () {
      expect(result.blockedPackages, expectedBlocked,
          reason: _drift(barrel, result));
    });

    test('the walk traversed the tree', () {
      expect(result.missingFiles, isEmpty,
          reason:
              'Imported but not found. A renamed or deleted file makes this '
              'gate report less than it should:\n'
              '${result.missingFiles.map((f) => '  $f').join('\n')}');
      expect(result.filesWalked, greaterThan(minFilesWalked),
          reason: 'The walk visited only ${result.filesWalked} files, fewer '
              'than the $minFilesWalked this baseline was taken at. Package '
              'resolution is probably broken — in which case the two '
              'assertions above passed by finding nothing.');
    });
  });
}

String _drift(String barrel, Shakedown result) => '''
The reachable platform libraries under $barrel have changed.

This is a two-way ratchet. A NEW entry means a browser-hostile import was
introduced. A MISSING entry means a blocker was fixed and this baseline should
shrink — which is the good direction, and still needs a deliberate edit.

Regenerate with:
  dart run wasm_shakedown:baseline $barrel

What the walk found (${result.filesWalked} files):
${result.report()}
''';
