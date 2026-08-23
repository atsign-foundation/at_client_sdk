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
void provenIn(String path, String testName, {required String proves}) {
  _record(path, testName, proves);

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
void _record(String path, String testName, String proves) {
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
          })}\n',
      mode: FileMode.append);
}
