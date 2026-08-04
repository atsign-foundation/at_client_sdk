/// Claiming a scenario whose proof lives in another package.
///
/// Half this catalogue's rows are proven against a live atServer, in
/// `tests/at_functional_test` or `tests/at_end2end_test`. Those are separate
/// packages, so this suite — which runs inside `at_client`'s unit tests — can
/// never observe them. Before this existed, a scenario proven live could never
/// turn its own row green, and the burn-down read as a floor rather than a
/// measure.
///
/// [provenIn] does **not** re-run the proof; it asserts the proof is still
/// where the row says it is. That is a weaker claim, and the weakness is the
/// honest part: what it buys is that the citation cannot rot silently. Rename
/// or delete the live test and this goes red, naming the row that just lost its
/// evidence — which is exactly how a live-proven row would otherwise decay into
/// an unnoticed lie.
///
/// A citation is a judgement that the named test really does establish the
/// scenario. Keep [proves] specific enough that the next reader can check that
/// judgement without opening the file.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Asserts the live proof for a scenario exists.
///
/// [path] is repo-relative. [testName] must match the start of a `test('…')`
/// name in that file. [proves] states what in that test establishes this row —
/// prose for a human, not matched against anything.
void provenIn(String path, String testName, {required String proves}) {
  final file = File('${repoRoot().path}/$path');
  expect(file.existsSync(), isTrue,
      reason: 'this row cites $path for its proof, and that file is gone — '
          'either restore it or the row is no longer proven');

  final source = file.readAsStringSync();
  expect(source.contains("'$testName"), isTrue,
      reason: 'this row cites "$testName" in $path, and no test there starts '
          'with that name. A renamed test is the same loss of evidence as a '
          'deleted one — re-point the citation or re-open the row. '
          '(What it was cited for: $proves)');
}

/// Walk up until the repo root is in reach, matching `catalogue_test.dart` so
/// both behave the same from a package root, the workspace root, or an IDE.
Directory repoRoot() {
  for (var dir = Directory.current;; dir = dir.parent) {
    if (File('${dir.path}/docs/projects/pq/acceptance.md').existsSync()) {
      return dir;
    }
    if (dir.path == dir.parent.path) {
      throw StateError(
          'could not locate the repo root from ${Directory.current}');
    }
  }
}
