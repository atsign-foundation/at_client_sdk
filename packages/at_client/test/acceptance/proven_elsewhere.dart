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

import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports, depend_on_referenced_packages
import 'package:test_api/src/backend/invoker.dart';
import 'package:test/test.dart';

import 'manifest.dart';

/// Where [provenIn] records each citation it makes, when asked to.
///
/// Unset, nothing is written and this file behaves exactly as it always has.
/// Set to a path, every citation is appended as one JSON object per line, and
/// `tool/acceptance_ledger.dart` joins those against the live packs' own
/// `--file-reporter json` output to say which rows were *actually exercised in
/// a run* rather than which citations still resolve.
///
/// Recorded rather than parsed out of the source: a regex over `provenIn(`
/// calls has to cope with the path sitting on the next line, which is the
/// formatting most of them use, and a matcher that quietly misses a third of
/// the corpus is how this project has been wrong before.
const _ledgerEnv = 'ACCEPTANCE_LEDGER';

/// Asserts the live proof for a scenario exists.
///
/// [path] is repo-relative. [testName] must match the start of a `test('…')`
/// name in that file. [proves] states what in that test establishes this row —
/// prose for a human, not matched against anything.
/// [clauses] pins which of the row's THEN clauses this citation claims.
///
/// Each entry is a distinctive fragment of one clause, and it must resolve to
/// exactly one — no match and more than one are both errors, because a pin
/// that resolves to nothing silently claims nothing while reading as coverage.
/// Fragments rather than indexes: inserting a clause must not re-point every
/// citation after it, and editing a clause's wording SHOULD break the pin, so
/// that the edit is reviewed against the test that proves it.
///
/// Omit it and the row keeps its old all-or-nothing verdict, which is why
/// leaving it off is not a failure — the ledger reports the row as having
/// unpinned clauses rather than pretending they are covered.
void provenIn(String path, String testName,
    {required String proves, List<String> clauses = const []}) {
  final pinned = _resolveClauses(clauses);
  _record(path, testName, proves, pinned);

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

/// Appends one citation, tagged with the scenario test that made it.
///
/// The scenario's own name carries the use-case id (`UC-A3.1 · …`), so the
/// ledger needs no separate row parameter and cannot disagree with the suite
/// about which row a citation belongs to.
void _record(String path, String testName, String proves, List<int> clauses) {
  final out = Platform.environment[_ledgerEnv];
  if (out == null || out.isEmpty) return;
  final scenario = Invoker.current?.liveTest.test.name;
  if (scenario == null) return;
  File(out).writeAsStringSync(
      '${jsonEncode({
            'scenario': scenario,
            'path': path,
            'testName': testName,
            'proves': proves,
            'clauses': clauses,
          })}\n',
      mode: FileMode.append);
}

/// The id of the row whose scenario is calling, or null for a cross-cutting
/// invariant — section 13's rows are deliberately unnumbered.
String? _callingUseCase() {
  final scenario = Invoker.current?.liveTest.test.name;
  if (scenario == null) return null;
  return RegExp(ucIdPattern).firstMatch(scenario)?.group(0);
}

/// Turns each pinned fragment into the clause index it names, asserting on the
/// way that it names exactly one.
List<int> _resolveClauses(List<String> pins) {
  if (pins.isEmpty) return const [];

  final useCase = _callingUseCase();
  expect(useCase, isNotNull,
      reason: 'clauses: can only be used from a scenario whose name carries a '
          'use-case id. A cross-cutting invariant has no catalogue row, so '
          'there are no clauses to pin');

  final available = clausesOf(useCase!);
  expect(available, isNotEmpty,
      reason: 'this citation pins clauses of $useCase and the catalogue states '
          'none for it. Either the row lost its THEN, or the parser in '
          'manifest.dart no longer recognises the form it is written in — '
          'check the row before deleting the pins');

  final resolved = <int>[];
  for (final pin in pins) {
    final hits = available.where((c) => c.text.contains(pin)).toList();
    expect(hits.length, 1,
        reason: hits.isEmpty
            ? 'no clause of $useCase contains "$pin". A pin that matches '
                'nothing claims nothing while reading as coverage. The '
                'clauses the catalogue states are:\n'
                '${available.map((c) => '  ${c.index}. ${c.text}').join('\n')}'
            : 'the fragment "$pin" matches ${hits.length} clauses of $useCase '
                '(${hits.map((c) => c.index).join(', ')}) — lengthen it until '
                'it names one');
    resolved.add(hits.single.index);
  }
  return resolved;
}

/// Claiming clauses a scenario proves **in its own body**.
///
/// Some rows assert inline rather than citing anything: the mechanism is a
/// transform over a document or a frame, so the whole proof fits in the
/// scenario. Before this they could pin nothing — [provenIn] takes a path, and
/// there is no other file to name — which meant the burn-down could never
/// count them and the clause total was unreachable however complete those
/// rows were.
///
/// An inline proof runs inside `at_client`'s unit suite, so it is in-process
/// by construction and never counts toward the server-proven column. That is
/// the honest reading and not a limitation of the recording: there is no
/// atServer in the loop.
void provenHere({required String proves, List<String> clauses = const []}) {
  final pinned = _resolveClauses(clauses);
  _record('(inline)', Invoker.current?.liveTest.test.name ?? '', proves, pinned);
}
