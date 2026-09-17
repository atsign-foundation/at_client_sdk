/// Guards the join in `tool/acceptance_ledger.dart`.
///
/// The ledger's whole value is that it can tell a row whose proof RAN from one
/// whose proof merely still exists, so a defect in that join does not look like
/// a defect — it looks like a coverage report.
///
/// The cases below pin both directions. A matcher that is too strict
/// under-reports and reads as missing coverage; one that is too loose reports
/// rows as proven by tests that never mention them, which is worse, because
/// nothing downstream would ever question a green.
library;

import 'package:test/test.dart';

import '../tool/acceptance_ledger.dart';

/// A citation to `f`, naming `t` — the shape `provenIn` records.
Citation _cite(String f, String t, {List<int> clauses = const []}) =>
    Citation('UC-X1.1', 'tests/pack/$f', t, 'why', clauses);

void main() {
  group('namesMatch', () {
    test('matches a test inside a group, which the runner reports prefixed',
        () {
      expect(
          namesMatch('A group of at client impl create tests test preference',
              'test preference'),
          isTrue,
          reason: 'the runner prepends enclosing group names and provenIn does '
              'not, so an anchored comparison drops every grouped test — most '
              'of both unit suites');
    });

    test('matches a citation that is a prefix of the test name', () {
      expect(
          namesMatch(
              'the readiness query says yes once the destination has '
                  'published a key',
              'says yes once the destination has published'),
          isTrue);
    });

    test('does not match an unrelated test in the same file', () {
      expect(
          namesMatch('the legacy escape hatch is shut by default',
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
      expect(
          verdictFor(_cite('cited_test.dart', 'the cited test name'), passed),
          'PROVEN');
    });

    test('FAILED when the cited test ran and did not pass', () {
      final failed = [
        RanTest('A group of things the cited test name', 'cited_test.dart',
            'failure'),
      ];
      expect(
          verdictFor(_cite('cited_test.dart', 'the cited test name'), failed),
          'FAILED');
    });

    test('NOT-EXERCISED when no report covers the cited file', () {
      expect(verdictFor(_cite('never_reported_test.dart', 'whatever'), passed),
          'NOT-EXERCISED');
    });

    test('NOT-EXERCISED when the file ran but the cited test did not', () {
      expect(
          verdictFor(
              _cite('cited_test.dart', 'a name nothing here carries'), passed),
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

  group('clause pinning', () {
    final passed = [
      RanTest('the cited test name', 'cited_test.dart', 'success')
    ];
    final failed = [RanTest('the cited test name', 'cited_test.dart', 'error')];

    test('a citation carries the clauses it pins', () {
      expect(
          _cite('cited_test.dart', 'the cited test name', clauses: [1, 4])
              .clauses,
          [1, 4]);
    });

    test('an unpinned citation claims no clause, not every clause', () {
      expect(_cite('cited_test.dart', 'the cited test name').clauses, isEmpty);
    });

    test('a pinned clause is only proven if its citation is', () {
      final c = _cite('cited_test.dart', 'the cited test name', clauses: [2]);
      expect(verdictFor(c, passed), 'PROVEN');
      expect(verdictFor(c, failed), 'FAILED');
      expect(verdictFor(c, const []), 'NOT-EXERCISED');
    });
  });
}
