/// Guards the burn-down itself.
///
/// The scenarios here were skipped placeholders while D1 was in flight; a
/// green build said nothing about whether this directory still mirrored the
/// catalogue. These checks are what did: they fail when a use case loses its
/// scenario, when a `skip:` and the blocker declaring it fall out of step in
/// either direction, or when the README's counts drift from the scenarios they
/// describe.
///
/// Catalogue: `docs/projects/pq/acceptance.md`.
library;

import 'dart:io';

import 'package:test/test.dart';

/// A use-case id as written in both the catalogue and a scenario's name.
final _ucId = RegExp(r'UC-[ABC]\d+\.\d+');

/// The same id at the start of a `test('UC-…')` name — the quote is what keeps
/// this to scenario names and out of the Given/When/Then prose.
final _scenarioName = RegExp(r"'(UC-[ABC]\d+\.\d+)");

void main() {
  final root = _repoRoot();
  final catalogue = File('${root.path}/docs/projects/pq/acceptance.md');
  final dir = Directory('${root.path}/packages/at_client/test/acceptance');
  final readme = File('${dir.path}/README.md');

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
    // The burn-down reached zero on 2026-08-08 and `blockers.dart` was deleted
    // rather than kept empty; this guard was replaced by one asserting the
    // mechanism stayed retired. KE-2 blocked rows again, so the file and this
    // cross-check came back together — which is the contract the retired guard
    // stated. A bare `skip:` with nothing declaring it hides a row from the
    // count with nobody recorded as owing it, and a constant that guards
    // nothing tells whoever greps it that the project owes no scenarios.
    final blockers = File('${dir.path}/blockers.dart');
    expect(blockers.existsSync(), isTrue,
        reason: 'a scenario skipped against a named blocker needs '
            'blockers.dart to declare it; if nothing is blocked any more, '
            'delete the file and restore the stays-retired guard with it');
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
    // Tracks the rows still SKIPPED. This has been re-pointed twice, each
    // time at whatever number was actually moving: first B-1's share, then
    // the owed-a-test backlog. Both reached zero, and a guard pinned to a
    // number that cannot change silently stops guarding.
    //
    // It asserts "skipped", not "blocked", because skipped is what it can
    // measure: a blocker's label (`blocked:` vs `owed:`) lived in
    // blockers.dart and was never visible here. Conflating the two is the
    // exact error decisions.md 35 caught, so this guard holds the total
    // honest and leaves the split to prose.
    final skipped = RegExp(r'skip: \w+\)').allMatches(source).length;
    final text = readme.readAsStringSync();

    final total = RegExp(r'\*\*(\d+) rows\*\*').firstMatch(text);
    expect(total, isNotNull,
        reason: 'README.md must state the row count as "**N rows**"');
    expect(int.parse(total![1]!), rows,
        reason: 'README.md says ${total[1]} rows; there are $rows');

    // `is` as well as `are`: the count reached one, and a guard that forces
    // "1 rows are skipped" is holding the prose to the regex rather than the
    // other way round.
    final skippedStated =
        RegExp(r'\*\*(\d+) of the (\d+)\*\* rows? (?:are|is) skipped')
            .firstMatch(text);
    expect(skippedStated, isNotNull,
        reason: 'README.md must state the skipped share as '
            '"**N of the M** rows are skipped"');
    expect(int.parse(skippedStated![1]!), skipped,
        reason: 'README.md says ${skippedStated[1]} skipped rows; there are '
            '$skipped. Landing a project changes this — update the README '
            'with it');
    expect(int.parse(skippedStated[2]!), rows);
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
