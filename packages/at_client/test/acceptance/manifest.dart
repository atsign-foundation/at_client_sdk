/// The acceptance ledger's own data, so its guards read a declaration rather
/// than infer one from prose.
///
/// Two things used to be inferred, and both could be fooled without anything
/// going red:
///
/// - **Which files hold burn-down rows.** The rule was "every `*_test.dart`
///   here except `catalogue_test.dart`", so adding any non-scenario file to
///   this directory silently inflated the row count the README is pinned to —
///   and the only way to add a guard without inflating it was to not add one.
/// - **Which use cases the catalogue defines.** The rule was every
///   `UC-…`-shaped string anywhere in `acceptance.md`, so a cross-reference
///   inside another row's prose counted as a catalogue entry. The defined set
///   and the mentioned set are still identical, which is luck rather than
///   construction: one typo'd cross-reference invents a use case that can never
///   have a scenario, and the guard would demand one forever.
///
///   ⚠️ This said "the same 43" until 2026-08-23, when the count was 69 — a
///   figure with no way to go red, since nothing reads it. Re-derive rather
///   than quoting one here, which is why no number replaces it:
///
///   ```bash
///   git grep -cP '^#{2,4} +(?:[\d.]+ +)?UC-[ABCG]\d+\.\d+[a-z]? +— ' \
///     -- docs/projects/pq/acceptance.md
///   ```
///
/// Both are declarations here now, and [undeclaredTestFiles] is what fails
/// when a file appears in this directory without being classified either way.
///
/// Catalogue: `docs/projects/pq/acceptance.md`.
library;

import 'dart:io';

/// Files whose `test(...)` calls are burn-down rows, counted by the README.
const scenarioFiles = <String>[
  'a1_onboard_test.dart',
  'a2_enrollment_test.dart',
  'a3_self_data_test.dart',
  'a4_shared_data_test.dart',
  'a5_rotation_test.dart',
  'b0_server_prereq_test.dart',
  'b1_retrofit_test.dart',
  'b2_retirement_test.dart',
  'b3_mixed_intra_test.dart',
  'b4_mixed_cross_test.dart',
  'b5_edge_cases_test.dart',
  'c1_rollout_test.dart',
  'g1_keyfile_test.dart',
  'g1_wire_test.dart',
  'g1_enroll_update_test.dart',
  'g1_rollout_matrix_test.dart',
  'cross_cutting_test.dart',
];

/// Files holding guards ABOUT the ledger or the source tree rather than
/// scenarios in it. Their tests are deliberately not rows: they would inflate
/// the burn-down with checks the catalogue never asked for.
const guardFiles = <String>[
  'architecture_guard_test.dart',
  'catalogue_test.dart',
  'docs_structure_test.dart',
];

/// A use case as the catalogue defines it — by a heading, not by a mention.
class UseCase {
  const UseCase(this.id, this.title);

  final String id;
  final String title;

  /// Whether the catalogue has withdrawn this row rather than owing it.
  ///
  /// A withdrawn row keeps its heading — the id stays resolvable, and the
  /// entry says why the row is not coming and what replaced it, which is the
  /// whole value of writing it down. Deleting the heading instead would leave
  /// every cross-reference to it dangling and lose the reason.
  ///
  /// So it must not be counted as owing a scenario: a burn-down that demands
  /// a test for a mechanism that was deleted can never reach zero.
  bool get isWithdrawn => title.startsWith('WITHDRAWN');

  @override
  String toString() => '$id — $title';
}

/// The shape of a use-case id, in ONE place.
///
/// ⚠️ **Widening the catalogue to a new cluster means widening this, and
/// nothing else.** It used to be spelled out in every regex that needed it —
/// three here and three in `docs_structure_test.dart` — and the ledger's note
/// about the last widening says "both of them, doc-side and test-side" because
/// there were two at the time. By 2026-08-18 there were six, the note still
/// said two, and adding the `G` cluster went red in a place that looked
/// unrelated: the status-table guard, whose own copy nobody had thought to
/// grep for.
///
/// The optional trailing letter is for a row inserted between two that were
/// already numbered — `UC-G1.9a` sits between 9 and 10 and is its own use
/// case. It does NOT capture the `(a)`/`(b)` suffix a SCENARIO uses to split
/// one row into two, because a bracket is not a letter: those still resolve to
/// the row they split.
const ucIdPattern = r'UC-[ABCG]\d+\.\d+[a-z]?';

/// Every heading that DEFINES a use case. The number prefix is optional
/// because the catalogue's first cluster has none.
///
/// ⚠️ **The letter class is what decides which clusters are enforced at all.**
/// It read `[ABC]` until 2026-08-18, so the sixteen `UC-G1.x` rows in
/// [acceptance.md section 16] were invisible to every check here — no heading
/// had to exist, no scenario had to cite one, and nothing compared the rows to
/// the tree. Eleven of the twelve that were then checked turned out to describe
/// code that had been deleted or reversed. Widening a cluster into this class
/// is what makes it real; adding rows to the document is not.
final _definition =
    RegExp('^#{2,4} +(?:[\\d.]+ +)?($ucIdPattern) +— +(.*)\$', multiLine: true);

/// A use-case id anywhere at all, definitions and cross-references alike.
/// The optional trailing letter is for a row inserted between two that were
/// already numbered — `UC-G1.9a` sits between 9 and 10 and is its own use
/// case, not a variant. It does NOT capture the `(a)`/`(b)` suffix a SCENARIO
/// uses to split one row into two, because a bracket is not a letter: those
/// still resolve to the row they split.
final _mention = RegExp(ucIdPattern);

/// The same id at the start of a `test('UC-…')` name — the quote is what keeps
/// this to scenario names and out of the Given/When/Then prose.
final _scenarioName = RegExp("test\\(\\s*'($ucIdPattern)");

/// Any `test(` at all, however its name is written.
final _anyScenario = RegExp(r'\btest\(');

/// A scenario skipped against a named blocker constant.
final _skip = RegExp(r'skip: (\w+)\)');

/// Walk up from the working directory until the catalogue is in reach, so
/// everything here runs the same from the package root, the workspace root, or
/// an IDE.
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

Directory acceptanceDir() =>
    Directory('${repoRoot().path}/packages/at_client/test/acceptance');

File catalogueFile() =>
    File('${repoRoot().path}/docs/projects/pq/acceptance.md');

String _read(String fileName) =>
    File('${acceptanceDir().path}/$fileName').readAsStringSync();

/// The use cases the catalogue DEFINES, in catalogue order.
List<UseCase> catalogueUseCases() => _definition
    .allMatches(catalogueFile().readAsStringSync())
    .map((m) => UseCase(m[1]!, m[2]!.trim()))
    .toList();

/// Every use-case id the catalogue mentions, including cross-references.
Set<String> catalogueMentions() => _mention
    .allMatches(catalogueFile().readAsStringSync())
    .map((m) => m[0]!)
    .toSet();

/// How many rows the burn-down has, read from the declared scenario files
/// only.
///
/// Deliberately not a directory listing: a file has to be declared in
/// [scenarioFiles] to be counted, so a guard added beside these cannot join
/// the count by existing.
int scenarioCount() => scenarioFiles
    .map((f) => _anyScenario.allMatches(_read(f)).length)
    .reduce((a, b) => a + b);

/// How many of those rows are skipped.
///
/// "Skipped", not "blocked": a blocker's label (`blocked:` vs `owed:`) lives
/// in `blockers.dart` and is not visible from a `skip:`. Conflating the two is
/// the error `decisions.md` 35 caught, so this counts what it can see and
/// leaves the split to prose.
int skippedCount() => scenarioFiles
    .map((f) => _skip.allMatches(_read(f)).length)
    .reduce((a, b) => a + b);

/// The use cases the scenarios claim, by name.
Set<String> scenarioUseCaseIds() {
  final ids = <String>{};
  for (final file in scenarioFiles) {
    ids.addAll(_scenarioName.allMatches(_read(file)).map((m) => m[1]!));
  }
  return ids;
}

/// Blocker constants `blockers.dart` declares, if the file exists.
Set<String> declaredBlockers() {
  final file = File('${acceptanceDir().path}/blockers.dart');
  if (!file.existsSync()) return <String>{};
  return RegExp(r'^const (\w+) =', multiLine: true)
      .allMatches(file.readAsStringSync())
      .map((m) => m[1]!)
      .where((name) => !name.startsWith('_'))
      .toSet();
}

/// Which use cases have a skipped scenario, and the blocker each is skipped
/// against.
///
/// Attributed per scenario, not per file. [skippedCount] only has to total the
/// skips, but the catalogue's status table has to say *which* use case is
/// blocked — and a file holds both running and skipped scenarios, so a
/// file-level answer would mark every use case in `a2_enrollment_test.dart`
/// blocked when two of its six are.
Map<String, String> skippedUseCases() {
  final out = <String, String>{};
  for (final file in scenarioFiles) {
    final text = _read(file);
    // Slice at each `test(` so a `skip:` belongs to the scenario it closes
    // rather than to whichever one happens to sit nearest it in the file.
    final starts = _anyScenario.allMatches(text).map((m) => m.start).toList();
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : text.length;
      final chunk = text.substring(starts[i], end);
      final named = _scenarioName.firstMatch(chunk);
      if (named == null) continue;
      final skipped = _skip.firstMatch(chunk);
      if (skipped != null) out[named.group(1)!] = skipped.group(1)!;
    }
  }
  return out;
}

/// Blocker constants the scenarios actually skip against.
Set<String> usedBlockers() {
  final used = <String>{};
  for (final file in scenarioFiles) {
    used.addAll(_skip.allMatches(_read(file)).map((m) => m[1]!));
  }
  return used;
}

/// Every `*_test.dart` in this directory, whether declared or not.
List<String> testFilesOnDisk() => acceptanceDir()
    .listSync()
    .whereType<File>()
    .map((f) => f.uri.pathSegments.last)
    .where((name) => name.endsWith('_test.dart'))
    .toList()
  ..sort();

/// Files present but classified as neither a scenario file nor a guard.
List<String> undeclaredTestFiles() => testFilesOnDisk()
    .where((f) => !scenarioFiles.contains(f) && !guardFiles.contains(f))
    .toList();

/// Files declared but not present.
List<String> missingDeclaredFiles() => [...scenarioFiles, ...guardFiles]
    .where((f) => !testFilesOnDisk().contains(f))
    .toList();

/// One THEN clause of a catalogue row — the unit a scenario can claim.
///
/// A row's verdict has always been all-or-nothing: cite one live test and the
/// whole row reads as proven, however many separate things its THEN states.
/// UC-A2.5 states six, and the one known overclaim in this catalogue — three
/// clauses of UC-A2.5/UC-A2.6 that no test reached — was found by hand,
/// because nothing could compute it.
class Clause {
  const Clause(this.useCase, this.index, this.text);

  /// The row this clause belongs to.
  final String useCase;

  /// Position within the row, from 1, in catalogue order.
  ///
  /// For reporting only. A citation names a clause by a distinctive fragment
  /// of its text, never by this number, so inserting a clause does not
  /// silently re-point every citation after it.
  final int index;

  /// The clause as written, collapsed to one line.
  final String text;

  @override
  String toString() => '$useCase clause $index: $text';
}

/// The two forms a THEN takes in this catalogue.
///
/// Most rows write `- **Then:**` bullets. The `UC-G1.x` cluster writes an
/// indented `*Then*` / `*And*` italic instead, and it is 16 of the 69 rows —
/// a parser that knows only the bullet form reports them as having no clauses
/// at all, which reads as "nothing to prove" rather than "I cannot see them".
final _thenBullet = RegExp(r'^- \*\*Then');
final _thenItalic = RegExp(r'^\s*\*(?:Then|And)\*');
final _subBullet = RegExp(r'^  - ');
final _anyBullet = RegExp(r'^- \*\*');
final _anyHeading = RegExp(r'^#{2,4} ');

String _collapse(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Every THEN clause the catalogue states, in catalogue order, keyed by row.
///
/// A `**Then:**` bullet carrying sub-bullets contributes its sub-bullets and
/// not itself: the bullet is then a heading for them, and counting both would
/// double every multi-clause row. A `**Then:**` with no sub-bullets is one
/// clause, whatever its prose asserts — the document's own structure is the
/// authority here, not a reading of the sentence.
///
/// A withdrawn row yields none, which is correct rather than a gap.
Map<String, List<Clause>> catalogueClauses() {
  final lines = catalogueFile().readAsStringSync().split('\n');
  final defs = <int, UseCase>{};
  for (var i = 0; i < lines.length; i++) {
    final m = _definition.firstMatch(lines[i]);
    if (m != null) defs[i] = UseCase(m[1]!, m[2]!.trim());
  }
  final starts = defs.keys.toList()..sort();
  final out = <String, List<Clause>>{};
  for (var n = 0; n < starts.length; n++) {
    final useCase = defs[starts[n]]!;
    final end = n + 1 < starts.length ? starts[n + 1] : lines.length;
    final body = lines.sublist(starts[n], end);
    final texts = <String>[];
    var j = 0;
    while (j < body.length) {
      if (_thenBullet.hasMatch(body[j])) {
        var k = j + 1;
        final subs = <String>[];
        while (k < body.length &&
            !_anyBullet.hasMatch(body[k]) &&
            !_anyHeading.hasMatch(body[k])) {
          if (_subBullet.hasMatch(body[k])) {
            final buffer = StringBuffer(body[k]);
            var c = k + 1;
            while (c < body.length &&
                !_subBullet.hasMatch(body[c]) &&
                !_anyBullet.hasMatch(body[c]) &&
                !_anyHeading.hasMatch(body[c]) &&
                body[c].trim().isNotEmpty) {
              buffer.write(' ${body[c]}');
              c++;
            }
            subs.add(_collapse(buffer.toString().substring(4)));
          }
          k++;
        }
        if (subs.isEmpty) {
          final buffer = StringBuffer(body[j]);
          var c = j + 1;
          while (c < body.length &&
              !_anyBullet.hasMatch(body[c]) &&
              !_anyHeading.hasMatch(body[c]) &&
              body[c].trim().isNotEmpty) {
            buffer.write(' ${body[c]}');
            c++;
          }
          texts.add(_collapse(buffer.toString().substring(2)));
        } else {
          texts.addAll(subs);
        }
        j = k;
        continue;
      }
      if (_thenItalic.hasMatch(body[j])) {
        final buffer = StringBuffer(body[j]);
        var c = j + 1;
        while (c < body.length &&
            !_thenItalic.hasMatch(body[c]) &&
            !_anyBullet.hasMatch(body[c]) &&
            !_anyHeading.hasMatch(body[c]) &&
            body[c].trim().isNotEmpty) {
          buffer.write(' ${body[c]}');
          c++;
        }
        texts.add(_collapse(buffer.toString()));
        j = c;
        continue;
      }
      j++;
    }
    out[useCase.id] = [
      for (var i = 0; i < texts.length; i++)
        Clause(useCase.id, i + 1, texts[i]),
    ];
  }
  return out;
}

/// The clauses of one row, or an empty list if the catalogue has no such row.
List<Clause> clausesOf(String useCase) =>
    catalogueClauses()[useCase] ?? const [];
