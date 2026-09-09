/// Renders the acceptance ledger: every catalogue row, and whether the live
/// test it cites actually ran and passed **in this set of runs**.
///
/// It reports what it observed rather than a verdict: `NOT-EXERCISED` means
/// "no report covering that file was supplied", never "broken". A row can only
/// be shown as proven by a run that actually happened.
///
/// Usage:
///   dart run tool/acceptance_ledger.dart \
///     --citations `<file written by ACCEPTANCE_LEDGER>` \
///     --report `<pack1.json>` [--report `<pack2.json>` ...] \
///     [--out `<ledger.md>`]
///
/// The citations file comes from running the acceptance suite with
/// `ACCEPTANCE_LEDGER=<path>`; each report comes from a pack run with
/// `--file-reporter json:<path>`.
library;

import 'dart:convert';
import 'dart:io';

import '../test/acceptance/manifest.dart' show Clause, catalogueClauses;

/// One `provenIn` call, as recorded while the acceptance suite ran.
class Citation {
  Citation(this.useCase, this.path, this.testName, this.proves, this.clauses);

  final String useCase;
  final String path;
  final String testName;
  final String proves;

  /// Which of the row's THEN clauses this citation claims, by index from 1.
  ///
  /// Empty means the citation claims the row as a whole — "unpinned", never
  /// "claims nothing".
  final List<int> clauses;

  String get file => path.split('/').last;
}

/// A test the runner reported, from a `--file-reporter json` stream.
class RanTest {
  RanTest(this.name, this.file, this.result);

  final String name;
  final String file;
  final String result;

  bool get passed => result == 'success';
}

final _ucInName = RegExp(r'UC-[A-Z][0-9]+\.[0-9]+[a-z]*');

/// The prefix `package:test` puts on a scenario name from its enclosing
/// `group`. Stripped so the invariant reads as itself.
const _invariantGroup = 'cross-cutting invariants ';

/// Marks a citation as belonging to a cross-cutting invariant rather than a
/// numbered row, keeping the invariant's own wording as the key.
String invariantKey(String scenario) =>
    'INV: ${scenario.startsWith(_invariantGroup) ? scenario.substring(_invariantGroup.length) : scenario}';

/// Reads the citation stream the acceptance suite writes, one JSON object per
/// line.
List<Citation> readCitations(File f) {
  final out = <Citation>[];
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final m = jsonDecode(line) as Map<String, dynamic>;
    final scenario = m['scenario'] as String;
    // NOTE: a scenario with no use-case id is a cross-cutting invariant, not a
    // defect — those rows apply to every flow and are deliberately unnumbered,
    // so they are keyed by their own name.
    final id =
        _ucInName.firstMatch(scenario)?.group(0) ?? invariantKey(scenario);
    out.add(Citation(
        id,
        m['path'] as String,
        m['testName'] as String,
        m['proves'] as String,
        [...?(m['clauses'] as List<dynamic>?)?.map((e) => e as int)]));
  }
  return out;
}

/// Every non-hidden test the runner reported, keyed by nothing — the caller
/// matches on file and name prefix.
///
/// The runner's own scaffolding is marked `hidden` and left out, so it cannot
/// count as proof.
List<RanTest> readReport(File f) {
  final byId = <int, Map<String, dynamic>>{};
  final out = <RanTest>[];
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final Map<String, dynamic> e;
    try {
      e = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      continue; // the stream carries a non-JSON preamble in some versions
    }
    switch (e['type']) {
      case 'testStart':
        final t = e['test'] as Map<String, dynamic>;
        byId[t['id'] as int] = t;
      case 'testDone':
        final t = byId[e['testID'] as int];
        if (t == null || (e['hidden'] as bool? ?? false)) continue;
        final url = (t['url'] ?? t['root_url']) as String? ?? '';
        out.add(RanTest(t['name'] as String, url.split('/').last,
            e['result'] as String? ?? 'unknown'));
    }
  }
  return out;
}

/// Finds the catalogue by walking up from the working directory.
///
/// Null when no directory within eight levels holds it, so the caller can say
/// so rather than throwing.
File? findCatalogue() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    final f = File('${dir.path}/docs/projects/pq/acceptance.md');
    if (f.existsSync()) return f;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// The catalogue's own row set, read from the status table so the ledger
/// cannot disagree with it about which rows exist.
Map<String, String> readCatalogue(File f) {
  final rows = <String, String>{};
  final re = RegExp(
      r'^\|\s*(UC-[A-Z][0-9]+\.[0-9]+[a-z]*)\s*\|\s*([^|]+?)\s*\|',
      multiLine: true);
  for (final m in re.allMatches(f.readAsStringSync())) {
    rows[m.group(1)!] = m.group(2)!;
  }
  return rows;
}

/// Whether [reported] is the test [cited] names.
///
/// ⚠️ **The runner prepends every enclosing `group` name, a citation does
/// not**, so the match is `contains` rather than `startsWith`: a citation is
/// already a prefix of the test's own name, and the only thing tolerated here
/// is the group prefix in front of it.
bool namesMatch(String reported, String cited) => reported.contains(cited);

/// Whether [c]'s cited test ran and passed in [ran], as one of `PROVEN`,
/// `FAILED` or `NOT-EXERCISED`.
String verdictFor(Citation c, List<RanTest> ran) {
  final inFile = ran.where((r) => r.file == c.file).toList();
  if (inFile.isEmpty) return 'NOT-EXERCISED';
  final matched = inFile.where((r) => namesMatch(r.name, c.testName)).toList();
  if (matched.isEmpty) return 'NOT-EXERCISED';
  return matched.every((r) => r.passed) ? 'PROVEN' : 'FAILED';
}

void main(List<String> args) {
  String? citationsPath, outPath;
  final reportPaths = <String>[];
  for (var i = 0; i < args.length - 1; i++) {
    switch (args[i]) {
      case '--citations':
        citationsPath = args[++i];
      case '--report':
        reportPaths.add(args[++i]);
      case '--out':
        outPath = args[++i];
    }
  }
  if (citationsPath == null) {
    stderr.writeln('--citations is required; see this file\'s dartdoc');
    exit(2);
  }

  final citations = readCitations(File(citationsPath));
  final ran = [for (final p in reportPaths) ...readReport(File(p))];
  final catalogueFile = findCatalogue();
  if (catalogueFile == null) {
    stderr.writeln('cannot find docs/projects/pq/acceptance.md from '
        '${Directory.current.path} or any parent — run this from inside the '
        'repository');
    exit(2);
  }
  final catalogue = readCatalogue(catalogueFile);

  final byUseCase = <String, List<Citation>>{};
  for (final c in citations) {
    byUseCase.putIfAbsent(c.useCase, () => []).add(c);
  }

  final b = StringBuffer()
    ..writeln('# Acceptance ledger')
    ..writeln()
    ..writeln('Generated by `tool/acceptance_ledger.dart`. Every row of '
        '`docs/projects/pq/acceptance.md`, and whether the live test it cites '
        'ran and passed in the runs supplied.')
    ..writeln()
    ..writeln('- **PROVEN** — a cited test ran in one of these reports and '
        'passed.')
    ..writeln('- **FAILED** — a cited test ran and did not pass.')
    ..writeln('- **NOT-EXERCISED** — no supplied report covers that file. This '
        'is a statement about the runs, not about the code.')
    ..writeln('- **NO-LIVE-CITATION** — the row proves itself in-process, so '
        'there is nothing here to exercise.')
    ..writeln('- **Clauses** — how many of the row\'s THEN clauses a PROVEN '
        'citation pins, out of how many the catalogue states. A row can read '
        'PROVEN with most of its clauses unpinned; that is the gap this '
        'column exists to show.')
    ..writeln()
    ..writeln(
        'Reports read: ${reportPaths.isEmpty ? "none" : reportPaths.join(", ")}')
    ..writeln('Tests reported: ${ran.length}   Citations: ${citations.length}')
    ..writeln()
    ..writeln('| Use case | Verdict | Clauses | Where |')
    ..writeln('|---|---|---|---|');

  final clausesByRow = catalogueClauses();

  /// Which clause indexes of [id] a PROVEN citation pins.
  Set<int> provenClauses(String id, List<Citation> cites) => {
        for (final c in cites)
          if (verdictFor(c, ran) == 'PROVEN') ...c.clauses,
      };

  final clauseGaps = <String, ({int total, Set<int> proven})>{};
  final tally = <String, int>{};
  for (final id in catalogue.keys) {
    final cites = byUseCase[id] ?? const <Citation>[];
    // NOTE: counted before the early return, or a row with no live citation
    // drops its clauses out of the denominator entirely.
    final rowClauses = clausesByRow[id]?.length ?? 0;
    if (cites.isEmpty) {
      tally['NO-LIVE-CITATION'] = (tally['NO-LIVE-CITATION'] ?? 0) + 1;
      if (rowClauses > 0) {
        clauseGaps[id] = (total: rowClauses, proven: const <int>{});
      }
      b.writeln('| $id | NO-LIVE-CITATION | 0/$rowClauses | — |');
      continue;
    }
    final verdicts = [for (final c in cites) verdictFor(c, ran)];
    // Worst verdict wins: a row is not proven because one of its several
    // citations happened to run.
    final v = verdicts.contains('FAILED')
        ? 'FAILED'
        : verdicts.contains('NOT-EXERCISED')
            ? 'NOT-EXERCISED'
            : 'PROVEN';
    tally[v] = (tally[v] ?? 0) + 1;
    final where = cites.map((c) => '`${c.file}`').toSet().join(', ');
    final proven = provenClauses(id, cites);
    if (rowClauses > 0) {
      clauseGaps[id] = (total: rowClauses, proven: proven);
    }
    b.writeln('| $id | $v | ${proven.length}/$rowClauses | $where |');
  }

  // Every row whose clauses are not all pinned by a proven citation: what the
  // tests ASSERT, rather than whether they ran.
  final gaps = clauseGaps.entries
      .where((e) => e.value.proven.length < e.value.total)
      .toList();
  if (gaps.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Clauses not covered by a proven citation')
      ..writeln()
      ..writeln('A citation pins clauses with `clauses:` in the scenario. An '
          'unpinned clause is one no citation claims — a gap in the *claims*, '
          'which may or may not be a gap in the tests. A pinned clause whose '
          'citation did not run is not counted as proven here, for the same '
          'reason NOT-EXERCISED is not PROVEN above.')
      ..writeln();
    for (final e in gaps) {
      final all = clausesByRow[e.key]!;
      b
        ..writeln('**${e.key}** — ${e.value.proven.length} of '
            '${e.value.total} clauses proven')
        ..writeln();
      for (final c in all) {
        final mark = e.value.proven.contains(c.index) ? 'x' : ' ';
        b.writeln('- [$mark] ${_oneLine(c)}');
      }
      b.writeln();
    }
  }

  // The cross-cutting invariants apply to every flow and so carry no number;
  // they get their own table rather than a row in the numbered one.
  final invariants = byUseCase.keys.where((k) => k.startsWith('INV: ')).toList()
    ..sort();
  if (invariants.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Cross-cutting invariants')
      ..writeln()
      ..writeln('[Section 13](../../../docs/projects/pq/acceptance.md) rows. '
          'They apply to every flow, so they are unnumbered and sit outside the '
          'use-case table above.')
      ..writeln()
      ..writeln('| Invariant | Verdict | Where |')
      ..writeln('|---|---|---|');
    for (final k in invariants) {
      final cites = byUseCase[k]!;
      final verdicts = [for (final c in cites) verdictFor(c, ran)];
      final v = verdicts.contains('FAILED')
          ? 'FAILED'
          : verdicts.contains('NOT-EXERCISED')
              ? 'NOT-EXERCISED'
              : 'PROVEN';
      tally['INVARIANT $v'] = (tally['INVARIANT $v'] ?? 0) + 1;
      final where = cites.map((c) => '`${c.file}`').toSet().join(', ');
      b.writeln('| ${k.substring(5)} | $v | $where |');
    }
  }

  b
    ..writeln()
    ..writeln('## Totals')
    ..writeln();
  for (final e in (tally.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key)))) {
    b.writeln('- ${e.key}: ${e.value}');
  }
  b.writeln('- rows in catalogue: ${catalogue.length}');
  final clauseTotal = clauseGaps.values.fold<int>(0, (a, e) => a + e.total);
  final clauseProven =
      clauseGaps.values.fold<int>(0, (a, e) => a + e.proven.length);
  b
    ..writeln('- clauses in catalogue: $clauseTotal')
    ..writeln('- clauses pinned by a proven citation: $clauseProven')
    ..writeln('- clauses with no proven citation: '
        '${clauseTotal - clauseProven}');

  if (outPath == null) {
    stdout.write(b);
  } else {
    File(outPath).writeAsStringSync(b.toString());
    stdout.writeln('wrote $outPath — ${catalogue.length} rows, '
        '${citations.length} citations, ${ran.length} tests reported');
  }
}

/// One clause, short enough for a checklist line and long enough to identify.
String _oneLine(Clause c) {
  final t = c.text.replaceAll('\n', ' ');
  return t.length <= 110
      ? '${c.index}. $t'
      : '${c.index}. ${t.substring(0, 108)}…';
}
