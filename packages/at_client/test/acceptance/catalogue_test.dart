/// Guards the burn-down itself.
///
/// Every other test here is a skipped placeholder, so a green build says nothing
/// about whether this directory still mirrors the catalogue. These checks are
/// **not** skipped: they fail when a use case loses its scenario, when a blocker
/// constant stops guarding anything, or when the README's counts drift from the
/// scenarios they describe.
///
/// Catalogue: `docs/projects/pq/acceptance.md`.
library;

import 'dart:io';

import 'package:test/test.dart';

/// A use-case id as written in both the catalogue and a scenario's name.
final _ucId = RegExp(r'UC-[AB]\d+\.\d+');

/// The same id at the start of a `test('UC-…')` name — the quote is what keeps
/// this to scenario names and out of the Given/When/Then prose.
final _scenarioName = RegExp(r"'(UC-[AB]\d+\.\d+)");

void main() {
  final root = _repoRoot();
  final catalogue = File('${root.path}/docs/projects/pq/acceptance.md');
  final dir = Directory('${root.path}/packages/at_client/test/acceptance');
  final readme = File('${dir.path}/README.md');
  final blockers = File('${dir.path}/blockers.dart');

  /// Every scenario file — this guard excluded, since it holds no scenarios.
  final scenarios = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_test.dart'))
      .where((f) => !f.path.endsWith('catalogue_test.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  String allScenarioSource() =>
      scenarios.map((f) => f.readAsStringSync()).join('\n');

  test('every use case in the catalogue has a scenario, and vice versa', () {
    final inCatalogue = _ucId
        .allMatches(catalogue.readAsStringSync())
        .map((m) => m[0]!)
        .toSet();
    final inTests =
        _scenarioName.allMatches(allScenarioSource()).map((m) => m[1]!).toSet();

    expect(inCatalogue.difference(inTests), isEmpty,
        reason: 'catalogue use cases with no scenario in this directory — add '
            'one, or the burn-down under-counts what D1 owes');
    expect(inTests.difference(inCatalogue), isEmpty,
        reason: 'scenarios naming a use case the catalogue does not define');
  });

  test('every blocker constant guards at least one scenario', () {
    final declared = RegExp(r'^const (\w+) =', multiLine: true)
        .allMatches(blockers.readAsStringSync())
        .map((m) => m[1]!)
        .where((name) => !name.startsWith('_'))
        .toSet();
    final used = RegExp(r'skip: (\w+)\)')
        .allMatches(allScenarioSource())
        .map((m) => m[1]!)
        .toSet();

    expect(declared.difference(used), isEmpty,
        reason: 'a blocker that guards nothing tells whoever greps it that the '
            'project owes no scenarios — delete it, or use it');
    expect(used.difference(declared), isEmpty,
        reason: 'skip: refers to a constant blockers.dart does not declare');
  });

  test('the README row counts match the scenarios', () {
    final source = allScenarioSource();
    final rows = RegExp(r'\btest\(').allMatches(source).length;
    // Tracks the *owed* rows rather than a single project's. B-1 used to be
    // the figure worth watching; it now gates nothing, and a guard pinned to a
    // finished project silently stops guarding anything.
    final owed =
        RegExp(r'skip: owed(Unit|Functional|E2e)\)').allMatches(source).length;
    final text = readme.readAsStringSync();

    final total = RegExp(r'\*\*(\d+) rows\*\*').firstMatch(text);
    expect(total, isNotNull,
        reason: 'README.md must state the row count as "**N rows**"');
    expect(int.parse(total![1]!), rows,
        reason: 'README.md says ${total[1]} rows; there are $rows');

    final owedStated =
        RegExp(r'owed rows gate \*\*(\d+) of the (\d+)\*\*').firstMatch(text);
    expect(owedStated, isNotNull,
        reason: 'README.md must state the owed share as '
            '"owed rows gate **N of the M**"');
    expect(int.parse(owedStated![1]!), owed,
        reason: 'README.md says ${owedStated[1]} owed rows; there are $owed. '
            'Writing one of them changes this — update the README with it');
    expect(int.parse(owedStated[2]!), rows);
  });
}

/// Walk up from the working directory until the catalogue is in reach, so this
/// runs the same from the package root, the workspace root, or an IDE.
Directory _repoRoot() {
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
