/// Guards the shape of `docs/projects/pq/`, which is a structure rather than a
/// convention.
///
/// The doc set is split in two on 2026-08-16: six **live** files carrying only
/// what is current, and `detail/` carrying every ruling body and every
/// completed or parked plan item. The split exists so that reading or grepping
/// a live file cannot drag a rejected design into view — the ledger reached
/// 10,126 lines and a search for one concept returned several hundred lines of
/// a decision nobody asked about.
///
/// A convention would not have held that. Every rule below was a convention
/// first, and the files grew anyway, so each is asserted here:
///
/// - the ledger index and the ruling bodies stay in step, both directions;
/// - no ruling body creeps back into the live ledger;
/// - each live file stays under a stated ceiling, so the way to add is to
///   demote something rather than to append;
/// - the catalogue's status table keeps saying what the scenarios do.
///
/// **A ceiling breach is not a failure of this test.** It means the file has
/// earned a demotion — move the finished part to `detail/`. Raising a ceiling
/// is legitimate and deliberate, and the edit is the review.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'manifest.dart';

Directory _pq() => Directory('${repoRoot().path}/docs/projects/pq');

String _read(String relative) =>
    File('${_pq().path}/$relative').readAsStringSync();

/// GitHub's heading-slug rule: lower-case, drop everything that is not a word
/// character, whitespace or a hyphen, then spaces become hyphens. Backticks go
/// first because they are markup rather than text.
String _slug(String heading) => heading
    .replaceAll('`', '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s-]'), '')
    .replaceAll(RegExp(r'\s'), '-');

Set<String> _headingSlugs(String markdown) => RegExp(r'^#{1,6}\s+(.*?)\s*$',
        multiLine: true)
    .allMatches(markdown)
    .map((m) => _slug(m.group(1)!))
    .toSet();

/// The live files and the most lines each may hold.
///
/// Measured at the split and given modest headroom. They are deliberately not
/// generous: a ceiling that nothing ever reaches enforces nothing.
const _ceilings = <String, int>{
  'decisions.md': 300,
  'implementation-plan.md': 1000,
  'acceptance.md': 1900,
  'design.md': 2450,
  'roadmap.md': 450,
  'seal-spec.md': 400,
};

void main() {
  group('the ledger index and its bodies stay in step', () {
    test('every index row resolves to a ruling body', () {
      final index = _read('decisions.md');
      final bodies = _headingSlugs(_read('detail/decisions.md'));

      final refs = RegExp(r'^\[([^\]]+)\]:\s*detail/decisions\.md#(\S+)\s*$',
              multiLine: true)
          .allMatches(index)
          .toList();

      expect(refs, isNotEmpty,
          reason: 'decisions.md must define its rows as reference links of the '
              'form "[104]: detail/decisions.md#...". Finding none means the '
              'index format changed and this guard is now checking nothing');

      final unresolved = refs
          .where((m) => !bodies.contains(m.group(2)))
          .map((m) => '[${m.group(1)}] -> #${m.group(2)}')
          .toList();

      expect(unresolved, isEmpty,
          reason: 'the ledger lists a ruling whose body is not in '
              'detail/decisions.md. A row without a body is a decision the '
              'reader cannot read the reasoning for, which is the one thing '
              'the index was never allowed to cost');
    });

    test('every ruling body is listed in the index', () {
      final index = _read('decisions.md');
      final listed = RegExp(r'^\[([0-9]+b?)\]:', multiLine: true)
          .allMatches(index)
          .map((m) => m.group(1)!)
          .toSet();

      // Section 0 is scope prose, not a ruling, so it is excluded by the
      // number requirement rather than by name.
      final bodies = RegExp(r'^## ([0-9]+b?)\. ', multiLine: true)
          .allMatches(_read('detail/decisions.md'))
          .map((m) => m.group(1)!)
          .where((n) => n != '0')
          .toSet();

      expect(bodies.difference(listed), isEmpty,
          reason: 'a ruling body exists with no row in decisions.md. Rulings '
              '102 and 103 were written without an index line once and the '
              'ledger disagreed with itself for a day - adding the row is '
              'part of adding the ruling');
      expect(listed.difference(bodies), isEmpty,
          reason: 'the index lists a ruling number with no body');
    });

    test('no ruling body creeps back into the live ledger', () {
      // A body announces itself with a `## <number>.` heading. The live file
      // holds the index and its prose, and nothing numbered.
      final stray = RegExp(r'^## [0-9]+b?\. .*$', multiLine: true)
          .allMatches(_read('decisions.md'))
          .map((m) => m.group(0)!)
          .toList();

      expect(stray, isEmpty,
          reason: 'decisions.md carries a ruling heading, so a body is being '
              'written into the index. Bodies belong in detail/decisions.md; '
              'this file exists so that grepping it returns headlines');
    });
  });

  group('the live files stay live', () {
    test('every live file is under its ceiling', () {
      final over = <String>[];
      for (final entry in _ceilings.entries) {
        final lines = _read(entry.key).split('\n').length;
        if (lines > entry.value) {
          over.add('${entry.key}: $lines lines, ceiling ${entry.value}');
        }
      }
      expect(over, isEmpty,
          reason: 'a live doc has grown past its ceiling. The fix is to demote '
              'the finished part to detail/, not to append here - accretion is '
              'exactly what produced a 10,126-line ledger and a 4,039-line '
              'plan. Raising a ceiling deliberately is fine, and that edit is '
              'the review');
    });

    test('every ceiling names a file that exists', () {
      // Otherwise a rename silently retires a ceiling, and the guard goes on
      // passing while the file it was written for grows unwatched.
      final missing = _ceilings.keys
          .where((f) => !File('${_pq().path}/$f').existsSync())
          .toList();
      expect(missing, isEmpty,
          reason: 'a ceiling names a file that is not there. If it was '
              'renamed, move the ceiling with it');
    });

    test('the detail files exist and hold the bulk', () {
      for (final f in const ['decisions.md', 'implementation-plan.md']) {
        final detail = File('${_pq().path}/detail/$f');
        expect(detail.existsSync(), isTrue,
            reason: 'detail/$f is where $f\'s history lives; without it the '
                'live file is not an index, it is a deletion');
        expect(detail.readAsStringSync().split('\n').length,
            greaterThan(_read(f).split('\n').length),
            reason: 'detail/$f is no larger than the live $f. Either the '
                'split was undone or the detail file was truncated');
      }
    });
  });

  group('the catalogue status table says what the scenarios do', () {
    // Rows look like: | UC-A2.5 | ... | BLOCKED | `ke2` |
    final row = RegExp(r'^\|\s*(UC-[ABC]\d+\.\d+)\s*\|[^|]*\|\s*(\w[\w ]*?)\s*\|',
        multiLine: true);

    test('every table row is a use case the catalogue defines', () {
      final defined = catalogueUseCases().map((u) => u.id).toSet();
      final rows =
          row.allMatches(_read('acceptance.md')).map((m) => m.group(1)!).toSet();

      expect(rows, isNotEmpty,
          reason: 'acceptance.md has no status rows. Either the table was '
              'removed or its shape changed, and this guard now checks '
              'nothing');
      expect(rows.difference(defined), isEmpty,
          reason: 'the status table names a use case with no heading');
      expect(defined.difference(rows), isEmpty,
          reason: 'a use case has a heading but no status row. The table is '
              'the index of the catalogue, so a missing row hides a use case '
              'from anyone reading the top of the file');
    });

    test('each row states the status the tree actually produces', () {
      final skipped = skippedUseCases();
      final claimed = scenarioUseCaseIds();
      final withdrawn = catalogueUseCases()
          .where((u) => u.isWithdrawn)
          .map((u) => u.id)
          .toSet();

      final wrong = <String>[];
      for (final m in row.allMatches(_read('acceptance.md'))) {
        final id = m.group(1)!;
        final stated = m.group(2)!.trim();
        final actual = withdrawn.contains(id)
            ? 'WITHDRAWN'
            : skipped.containsKey(id)
                ? 'BLOCKED'
                : claimed.contains(id)
                    ? 'PROVEN'
                    : 'NO SCENARIO';
        if (stated != actual) wrong.add('$id: table says $stated, tree says $actual');
      }

      expect(wrong, isEmpty,
          reason: 'the status table and the scenarios disagree. The table is '
              'generated from the tree, so the tree wins - regenerate it '
              'rather than editing the row. A hand-maintained status column '
              'is the "current state" table this project has been wrong about '
              'before');
    });
  });
}
