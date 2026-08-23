/// Guards the join in `tool/acceptance_ledger.dart`.
///
/// The ledger's whole value is that it can tell a row whose proof RAN from one
/// whose proof merely still exists, so a defect in that join does not look like
/// a defect — it looks like a coverage report. This exists because the first
/// version shipped exactly that: `startsWith` against a reported name, which
/// silently missed every test inside a `group`, scored 28 PROVEN where the
/// truth was 62, and was believable because the rows it dropped were ones whose
/// proof plausibly lives elsewhere.
///
/// So the cases below pin both directions. A matcher that is too strict
/// under-reports and reads as missing coverage; one that is too loose reports
/// rows as proven by tests that never mention them, which is worse, because
/// nothing downstream would ever question a green.
library;

import 'package:test/test.dart';

import '../tool/acceptance_ledger.dart';

/// A citation to `f`, naming `t` — the shape `provenIn` records.
Citation _cite(String f, String t) => Citation('UC-X1.1', 'tests/pack/$f', t, 'why');

void main() {
  group('namesMatch', () {
    test('matches a test inside a group, which the runner reports prefixed',
        () {
      // The exact regression. `provenIn` cites the test's own name; the runner
      // reports "<group> <name>". Anything anchored at the start fails here.
      expect(
          namesMatch('A group of at client impl create tests test preference',
              'test preference'),
          isTrue,
          reason: 'the runner prepends enclosing group names and provenIn does '
              'not, so an anchored comparison drops every grouped test — most '
              'of both unit suites');
    });

    test('matches a citation that is a prefix of the test name', () {
      // provenIn matches the START of a test name by design, so a citation is
      // routinely shorter than the test it names.
      expect(
          namesMatch('the readiness query says yes once the destination has '
              'published a key', 'says yes once the destination has published'),
          isTrue);
    });

    test('does not match an unrelated test in the same file', () {
      // The other direction, and the dangerous one: a matcher loose enough to
      // pair any citation with any test would report the catalogue fully proven
      // by a run that proved none of it.
      expect(namesMatch('the legacy escape hatch is shut by default',
              'says yes once the destination has published a key'),
          isFalse);
    });
  });

  group('verdictFor', () {
    final passed = [
      RanTest('A group of things the cited test name', 'cited_test.dart',
          'success'),
      RanTest('something else entirely', 'cited_test.dart', 'success'),
    ];

    test('PROVEN when the cited test ran and passed', () {
      expect(verdictFor(_cite('cited_test.dart', 'the cited test name'), passed),
          'PROVEN');
    });

    test('FAILED when the cited test ran and did not pass', () {
      final failed = [
        RanTest('A group of things the cited test name', 'cited_test.dart',
            'failure'),
      ];
      expect(verdictFor(_cite('cited_test.dart', 'the cited test name'), failed),
          'FAILED');
    });

    test('NOT-EXERCISED when no report covers the cited file', () {
      // The state a citation alone can never express, and the reason this tool
      // exists. It must not be reported as a failure: nothing is broken, the
      // run simply did not include that pack.
      expect(
          verdictFor(_cite('never_reported_test.dart', 'whatever'), passed),
          'NOT-EXERCISED');
    });

    test('NOT-EXERCISED when the file ran but the cited test did not', () {
      // A renamed or deleted test inside a file that still runs. Reporting the
      // row PROVEN here — because *something* in the file passed — is the
      // over-matching failure, and it would be invisible.
      expect(
          verdictFor(_cite('cited_test.dart', 'a name nothing here carries'),
              passed),
          'NOT-EXERCISED');
    });

    test('an empty report set proves nothing', () {
      expect(verdictFor(_cite('cited_test.dart', 'the cited test name'), []),
          'NOT-EXERCISED',
          reason: 'a ledger rendered with no reports must show the catalogue '
              'unproven, not proven by default');
    });
  });

  group('invariantKey', () {
    test('strips the group prefix the runner prepends', () {
      expect(invariantKey('cross-cutting invariants reads are universal'),
          'INV: reads are universal');
    });

    test('leaves a scenario carrying no group prefix alone', () {
      expect(invariantKey('reads are universal'), 'INV: reads are universal');
    });
  });
}
