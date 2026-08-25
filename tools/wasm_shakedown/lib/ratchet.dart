/// The shared shape of a per-package dependency-tree ratchet.
///
/// Each package's `test/wasm/dep_tree_test.dart` supplies its barrels and its
/// baselines; the assertions and the failure messages live here so that five
/// copies cannot drift into five slightly different notions of what the gate
/// promises.
///
/// ```dart
/// void main() {
///   ratchetGroup(
///     'package:at_lookup/at_lookup.dart',
///     package: 'at_lookup',
///     allowedOffenders: const {'lib/src/at_lookup_impl.dart'},
///     maxBlockedPackages: 3,
///     minFilesWalked: 600,
///   );
/// }
/// ```
library;

import 'package:test/test.dart';

import 'wasm_shakedown.dart';

/// Pins the platform libraries reachable from [barrel].
///
/// [allowedOffenders] is the set of [package]-owned sources permitted to reach a
/// forbidden library, keyed by package-relative path; [maxBlockedPackages] is a
/// ceiling on how many packages anywhere in the graph own an offender.
///
/// Both are **one-way**. A path outside [allowedOffenders] fails, and so does a
/// blocked count above the ceiling — but fixing a file, or dropping a dependency,
/// passes with no edit here. Only tightening a baseline needs a deliberate
/// change, which is the direction worth spending attention on.
///
/// [minFilesWalked] guards the whole thing. Every assertion here is about what
/// the walk did *not* find, and a traversal that stalled at the entry point also
/// finds nothing — so set it near the real figure, not to 1.
void ratchetGroup(
  String barrel, {
  required String package,
  required Set<String> allowedOffenders,
  required int maxBlockedPackages,
  required int minFilesWalked,
  Map<String, bool> environment = webEnvironment,
}) {
  group(barrel, () {
    late Shakedown result;
    late Set<String> owned;

    setUpAll(() {
      result = shakedown(barrel, environment: environment);
      owned = result.offendersIn(package).keys.toSet();
      // Printed on every run, pass or fail, so the CI log carries the figure
      // rather than only reporting the moment it gets worse.
      print('$barrel — ${result.filesWalked} files walked, '
          '${owned.length}/${allowedOffenders.length} offenders, '
          '${result.blockedPackages.length}/$maxBlockedPackages blocked');
    });

    test('no new browser-hostile import', () {
      final added = owned.difference(allowedOffenders).toList()..sort();
      expect(added, isEmpty,
          reason: 'These $package sources reach a forbidden platform library '
              'and are not in allowedOffenders:\n'
              '${added.map((p) => '  $p').join('\n')}\n\n'
              'If that is deliberate, add the path. Otherwise this is the '
              'regression the gate exists to catch.\n\n'
              'The full walk (${result.filesWalked} files):\n'
              '${result.report()}');

      expect(
          result.blockedPackages.length, lessThanOrEqualTo(maxBlockedPackages),
          reason: 'The graph under $barrel now has offenders in '
              '${result.blockedPackages.length} packages, over the '
              '$maxBlockedPackages this is baselined at:\n'
              '  ${(result.blockedPackages.toList()..sort()).join(', ')}');
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
              'resolution is probably broken — in which case the assertions '
              'above passed by finding nothing.');
    });
  });
}
