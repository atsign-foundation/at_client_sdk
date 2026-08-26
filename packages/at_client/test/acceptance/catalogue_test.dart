/// Guards the burn-down itself.
///
/// The scenarios here were skipped placeholders while D1 was in flight; a
/// green build said nothing about whether this directory still mirrored the
/// catalogue. These checks are what did: they fail when a use case loses its
/// scenario, when a `skip:` and the blocker declaring it fall out of step in
/// either direction, or when the README's counts drift from the scenarios they
/// describe.
///
/// What each guard reads is declared in `manifest.dart` rather than inferred
/// from prose or from a directory listing — see that file for the two ways the
/// inferred versions could be fooled without anything going red.
///
/// Catalogue: `docs/projects/pq/acceptance.md`.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'manifest.dart';

void main() {
  test('every use case in the catalogue has a scenario, and vice versa', () {
    final all = catalogueUseCases();
    final owed = all.where((u) => !u.isWithdrawn).map((u) => u.id).toSet();
    final withdrawn = all.where((u) => u.isWithdrawn).map((u) => u.id).toSet();
    final claimed = scenarioUseCaseIds();

    expect(owed.difference(claimed), isEmpty,
        reason: 'catalogue use cases with no scenario in this directory — add '
            'one, or the burn-down under-counts what D1 owes');
    expect(claimed.difference(owed), isEmpty,
        reason: 'scenarios naming a use case the catalogue does not define');
    expect(claimed.intersection(withdrawn), isEmpty,
        reason: 'a scenario is still proving a row the catalogue withdrew. '
            'The catalogue is the authority on what is owed, so either the '
            'withdrawal is wrong or the scenario is testing a mechanism that '
            'no longer exists');
  });

  test('every use case the catalogue mentions is one it defines', () {
    // A use case is defined by its heading. Before that was the rule, the set
    // was every UC-shaped string anywhere in acceptance.md, so a
    // cross-reference in one row's prose counted as a catalogue entry — and a
    // typo in one invented a use case that could never have a scenario and
    // would have been demanded forever.
    final defined = catalogueUseCases().map((u) => u.id).toSet();
    expect(catalogueMentions().difference(defined), isEmpty,
        reason: 'acceptance.md refers to a use case it never defines with a '
            'heading. Either it is a typo in a cross-reference, or a row was '
            'removed and something still points at it');
  });

  test('every blocker constant guards at least one scenario', () {
    // The burn-down reached zero on 2026-08-08 and `blockers.dart` was deleted
    // rather than kept empty; this guard was replaced by one asserting the
    // mechanism stayed retired. KE-2 blocked rows again, so the file and this
    // cross-check came back together — which is the contract the retired guard
    // stated. A bare `skip:` with nothing declaring it hides a row from the
    // count with nobody recorded as owing it, and a constant that guards
    // nothing tells whoever greps it that the project owes no scenarios.
    final blockers = File('${acceptanceDir().path}/blockers.dart');
    expect(blockers.existsSync(), isTrue,
        reason: 'a scenario skipped against a named blocker needs '
            'blockers.dart to declare it; if nothing is blocked any more, '
            'delete the file and restore the stays-retired guard with it');

    final declared = declaredBlockers();
    final used = usedBlockers();

    expect(declared.difference(used), isEmpty,
        reason: 'a blocker that guards nothing tells whoever greps it that the '
            'project owes no scenarios — delete it, or use it');
    expect(used.difference(declared), isEmpty,
        reason: 'skip: refers to a constant blockers.dart does not declare');
  });

  test('no use-case heading is invisible to the id pattern', () {
    // The guard that watches the guard.
    //
    // Narrowing `ucIdPattern` does NOT turn this suite red — it turns it
    // silently green, because the rows it stops admitting disappear from the
    // catalogue's view along with the scenarios that cite them, and the row
    // counts still reconcile because they are counted per FILE rather than per
    // id. Measured 2026-08-18: reverting the class to `UC-[ABC]` with sixteen
    // `UC-G1.x` rows and scenarios in place left the whole suite passing.
    //
    // That is how the G cluster went a week describing deleted code while
    // every rail was green. So this reads the headings with a DELIBERATELY
    // permissive pattern and asserts the real one admits each — a cluster can
    // only leave the catalogue on purpose, by deleting its rows.
    final permissive = RegExp(
        r'^#{2,4} +(?:[\d.]+ +)?(UC-[A-Z]+\d+\.\d+[a-z]?) +— ',
        multiLine: true);
    final admitted = RegExp('^$ucIdPattern\$');

    final headings = permissive
        .allMatches(catalogueFile().readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();

    expect(headings, isNotEmpty,
        reason: 'the permissive pattern found no use-case headings at all, so '
            'this guard is checking nothing — it has stopped matching the '
            'catalogue rather than the catalogue having emptied');

    final invisible = headings.where((id) => !admitted.hasMatch(id)).toSet();
    expect(invisible, isEmpty,
        reason: 'these use cases have headings the catalogue guards cannot '
            'see, because ucIdPattern does not admit them. Nothing else goes '
            'red for this: they simply stop being checked, and their rows are '
            'then free to drift from the tree. Widen ucIdPattern, or delete '
            'the rows deliberately');
  });

  test('the README row counts match the scenarios', () {
    final rows = scenarioCount();
    final skipped = skippedCount();
    final text = File('${acceptanceDir().path}/README.md').readAsStringSync();

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

  group('every row has live evidence, or a written reason it cannot', () {
    // The standing rule (gkc, 2026-08-26): a proof by mock is acceptable ONLY
    // where a live test would be prohibitively costly or impossible. Before
    // this, a row proven entirely in-process was indistinguishable from one
    // proven against a real atServer — the status table said PROVEN for both,
    // and half the catalogue was in the first group without anyone choosing
    // that.
    //
    // The rule needs a rail rather than prose because the doc has already
    // carried three stale claims about exactly this subject.

    test('no row rests on an in-process proof without a declared reason', () {
      final undeclared = (useCasesWithoutLiveProof()
            ..removeAll(liveProofExempt.keys)
            ..removeAll(liveProofOwed.keys))
          .toList()
        ..sort();

      expect(undeclared, isEmpty,
          reason: 'these rows cite no test in a live pack, and manifest.dart '
              'says nothing about why: ${undeclared.join(', ')}.\n'
              'Every row needs one of three things — a citation to a test in '
              '${livePackPaths.join(', ')}; an entry in liveProofExempt '
              'saying why a live test could add nothing; or an entry in '
              'liveProofOwed naming what owes it. Picking one is the point: '
              'the row that quietly stays on a mock is the one this catches');
    });

    test('a row does not claim both an exemption and a debt', () {
      final both = liveProofExempt.keys
          .where(liveProofOwed.containsKey)
          .toList()
        ..sort();

      expect(both, isEmpty,
          reason: 'a row cannot both be permanently exempt and owe a live '
              'test: ${both.join(', ')}. The two maps decay in opposite '
              'directions, so a row in both is a decision nobody has made');
    });

    test('a declared row is one the catalogue defines', () {
      final defined = catalogueUseCases().map((u) => u.id).toSet();
      final unknown = {...liveProofExempt.keys, ...liveProofOwed.keys}
          .difference(defined)
          .toList()
        ..sort();

      expect(unknown, isEmpty,
          reason: 'these are declared here but are not use cases the '
              'catalogue defines: ${unknown.join(', ')}. A typo\'d id is a '
              'waiver that can never be reviewed, because the row it names '
              'does not exist');
    });

    test('a row that has since been proven live loses its entry', () {
      // The direction nobody checks. An exemption or a debt outlives the state
      // that justified it, and a stale waiver reads exactly like a considered
      // one — so the map has to shrink when the tree improves, not just grow
      // when it does not.
      final withoutLive = useCasesWithoutLiveProof();
      final stale = {...liveProofExempt.keys, ...liveProofOwed.keys}
          .where((id) => !withoutLive.contains(id))
          .toList()
        ..sort();

      expect(stale, isEmpty,
          reason: 'these rows now cite a live test, so their entry in '
              'liveProofExempt / liveProofOwed is spent and must be deleted: '
              '${stale.join(', ')}');
    });

    test('every declared reason says something a reviewer can judge', () {
      final thin = <String>[];
      for (final entry in {...liveProofExempt, ...liveProofOwed}.entries) {
        if (entry.value.trim().length < 40) thin.add(entry.key);
      }
      thin.sort();

      expect(thin, isEmpty,
          reason: 'these reasons are too short to carry a judgement: '
              '${thin.join(', ')}. The reason is the whole value of the '
              'entry — "unit only" or "TODO" waives the rule without stating '
              'anything anybody can disagree with');
    });
  });

  group('the clause burn-down', () {
    // What "done" means, in the two columns gkc set (2026-08-26): every THEN
    // clause proven by something, and as many as feasible proven against a
    // real atServer. Row-level PROVEN cannot express either — a row reads
    // proven on one citation however many separate things its THEN states.

    test('the recorded counts are what the tree produces', () {
      var clauses = 0, proven = 0, server = 0;
      for (final u in catalogueUseCases().where((u) => !u.isWithdrawn)) {
        clauses += clausesOf(u.id).length;
        final cov = clauseCoverageOf(u.id);
        proven += cov.proven.length;
        server += cov.serverProven.length;
      }

      // Printed on every run, pass or fail: the burn-down is the reason this
      // guard exists, and a number only visible when something breaks is a
      // number nobody watches.
      // ignore: avoid_print
      print('BURN-DOWN  clauses proven: $proven of $clauses   '
          'server-proven: $server of $clauses');

      expect(proven, provenClauseCount,
          reason: 'the tree pins $proven of $clauses clauses and '
              'manifest.dart records $provenClauseCount.\n'
              'If you just landed a pin, raise provenClauseCount to $proven '
              'in the same commit — the count and the thing it counts move '
              'together, or the count becomes one more stale figure.\n'
              'If you did not, a pin stopped resolving: a clause was reworded '
              'and its fragment no longer matches');

      expect(server, serverProvenClauseCount,
          reason: 'the tree pins $server of $clauses clauses from a live '
              'pack and manifest.dart records $serverProvenClauseCount. '
              'Same rule: move them together');
    });

    test('every pin resolves to exactly one clause', () {
      // provenIn enforces this while a scenario RUNS, which covers the pins
      // on rows whose scenario executes. This says the same thing about the
      // sources, so a pin cannot be counted here and rejected there.
      final broken = <String>[];
      citationDetailsByUseCase().forEach((useCase, citations) {
        for (final citation in citations) {
          for (final pin in citation.pins) {
            final hits = resolvePin(useCase, pin);
            if (hits.length != 1) {
              broken.add('$useCase pin "$pin" -> ${hits.length} clauses');
            }
          }
        }
      });

      expect(broken, isEmpty,
          reason: 'a pin must name exactly one clause. Nothing matched means '
              'the citation claims nothing while reading as coverage; two '
              'means nobody can tell which:\n${broken.join('\n')}');
    });
  });
}
