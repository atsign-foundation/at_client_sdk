/// Renders the acceptance ledger: every catalogue row, and whether the live
/// test it cites actually ran and passed **in this set of runs**.
///
/// The problem it solves. `provenIn` asserts that a cited test still exists
/// under its name — a real guard against silent citation rot, but a weaker
/// claim than it reads as. It cannot tell a test that passed from one that was
/// never run, so a row stays green when the pack holding its proof did not
/// execute at all, and half the catalogue's PROVEN rows cite unit tests rather
/// than anything live. This joins the citations to the runners' own output and
/// says which is which.
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

/// One `provenIn` call, as recorded while the acceptance suite ran.
class Citation {
  Citation(this.useCase, this.path, this.testName, this.proves);

  final String useCase;
  final String path;
  final String testName;
  final String proves;

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

List<Citation> readCitations(File f) {
  final out = <Citation>[];
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final m = jsonDecode(line) as Map<String, dynamic>;
    final scenario = m['scenario'] as String;
    // A scenario with no use-case id is a CROSS-CUTTING INVARIANT, not a
    // defect: section 13's rows apply to every flow, so they are deliberately
    // unnumbered. They are keyed by their own name and reported in their own
    // table — dropping them would hide 14 of 135 citations, and inventing ids
    // for them would put a number in the catalogue that nothing else uses.
    final id =
        _ucInName.firstMatch(scenario)?.group(0) ?? invariantKey(scenario);
    out.add(Citation(id, m['path'] as String, m['testName'] as String,
        m['proves'] as String));
  }
  return out;
}

/// Every non-hidden test the runner reported, keyed by nothing — the caller
/// matches on file and name prefix.
///
/// `hidden` marks the runner's own scaffolding (`(setUpAll)`, the synthetic
/// "loading …" entry). Counting those as proof would make every suite look
/// like it proved something.
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
/// ⚠️ **The runner prepends every enclosing `group` name, `provenIn` does
/// not.** A citation names the test's own name — that is what
/// `proven_elsewhere.dart` matches against the source — while the reporter
/// emits `"<group> <name>"`. A `startsWith` comparison therefore misses every
/// grouped test, which is most of the unit suites: it scored 28 PROVEN where
/// the truth was higher, and looked entirely plausible because the rows it
/// missed were ones whose proof genuinely lives elsewhere.
///
/// `contains` is the correct generalisation rather than a loosening: a
/// citation is already a *prefix* of the test name by design, so the only
/// thing being tolerated here is the group prefix in front of it.
bool namesMatch(String reported, String cited) => reported.contains(cited);

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
  final catalogue = readCatalogue(
      File('${Directory.current.path}/../../docs/projects/pq/acceptance.md'));

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
    ..writeln()
    ..writeln(
        'Reports read: ${reportPaths.isEmpty ? "none" : reportPaths.join(", ")}')
    ..writeln('Tests reported: ${ran.length}   Citations: ${citations.length}')
    ..writeln()
    ..writeln('| Use case | Verdict | Where |')
    ..writeln('|---|---|---|');

  final tally = <String, int>{};
  for (final id in catalogue.keys) {
    final cites = byUseCase[id] ?? const <Citation>[];
    if (cites.isEmpty) {
      tally['NO-LIVE-CITATION'] = (tally['NO-LIVE-CITATION'] ?? 0) + 1;
      b.writeln('| $id | NO-LIVE-CITATION | — |');
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
    b.writeln('| $id | $v | $where |');
  }

  // The cross-cutting invariants: section 13's rows, which apply to every flow
  // and so carry no number. Reported separately rather than forced into the
  // numbered table, because a reader asking "is this row proven" and one asking
  // "does this invariant still hold" are asking different questions.
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

  if (outPath == null) {
    stdout.write(b);
  } else {
    File(outPath).writeAsStringSync(b.toString());
    stdout.writeln('wrote $outPath — ${catalogue.length} rows, '
        '${citations.length} citations, ${ran.length} tests reported');
  }
}
