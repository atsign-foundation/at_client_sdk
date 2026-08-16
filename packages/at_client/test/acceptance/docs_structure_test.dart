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
/// - the catalogue's status table keeps saying what the scenarios do;
/// - no doc licenses itself to leave a falsified claim standing.
///
/// **A ceiling breach is not a failure of this test.** It means the file has
/// earned a demotion — move the finished part to `detail/`. Raising a ceiling
/// is legitimate and deliberate, and the edit is the review.
///
/// ⚠️ **Correctness outranks every structural rule here, and only the
/// structural ones can be asserted.** Nothing in this file can tell whether a
/// paragraph is true, so the rails go red for a broken link, a ceiling breach
/// or a missing row, and stay green for a sentence the tree falsified three
/// commits ago. That asymmetry taught exactly the wrong lesson once: rulings
/// 104 and 105 were edited at every step, always by appending a layer under
/// prose that had stopped being true, until a cold read of the doc set
/// reported a settled design as an open question. The last group below is the
/// only part of that which is mechanically checkable — a doc may not write
/// down a rule permitting it.
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

    test('a ruling amended in its body says so in the index', () {
      // The status vocabulary reserves AMENDED for "stands, but one or more
      // sub-rulings were changed later, on the date given". Eleven rulings
      // carried a dated amendment in the body and `LIVE` in the index — the
      // marker is written while editing the body, and nothing takes the
      // author back to the row.
      final index = _read('decisions.md');
      // ⚠️ `[ \t]`, never `\s`: `\s` eats the newline and each match swallows
      // the following row, which silently halved a count here once.
      final status = <String, String>{
        for (final m in RegExp(
                r'^\|[ \t]*\[(\d+[a-z]?)\][ \t]*\|[^\n]*\|[^|\n]*\|[ \t]*([^|\n]+?)[ \t]*\|[ \t]*$',
                multiLine: true)
            .allMatches(index))
          m.group(1)!: m.group(2)!,
      };
      expect(status.length, greaterThan(100),
          reason: 'the ruling table did not parse, so this guard checks '
              'nothing. Its row shape must have changed');

      final amended = RegExp(r'\bAmended\b[^.\n]{0,12}?\(?(20\d\d-\d\d-\d\d)',
          caseSensitive: false);
      final bodies = _read('detail/decisions.md').split(RegExp(r'^## ', multiLine: true));

      final silent = <String>[];
      for (final body in bodies) {
        final head = RegExp(r'^(\d+[a-z]?)\. ').firstMatch(body);
        if (head == null) continue;
        final dates = amended.allMatches(body).map((m) => m.group(1)!).toList();
        if (dates.isEmpty) continue;
        final st = (status[head.group(1)] ?? '').toUpperCase();
        // A stronger not-in-force status already tells the reader to look.
        if (st.contains('AMENDED') || st.contains('SUPERSEDED') ||
            st.contains('REJECTED')) {
          continue;
        }
        silent.add('[${head.group(1)}] body says "Amended ${dates.last}", '
            'index says "${status[head.group(1)]}"');
      }
      expect(silent, isEmpty,
          reason: 'a ruling records its own amendment and the index does not:\n'
              '${silent.join('\n')}');
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

  group('no doc licenses itself to leave a falsified claim standing', () {
    /// Phrases that assert a *rule* permitting stale prose, rather than
    /// describing one document's history.
    ///
    /// Each was in the tree on 2026-08-16 and each had done real damage. They
    /// are banned rather than discouraged because their whole effect is to
    /// pre-authorise the next stale paragraph: once a doc says rulings are
    /// append-only, correcting one reads as a violation.
    ///
    /// ⚠️ **This is a check on doctrine, not on truth.** It cannot tell that a
    /// paragraph went stale — only that a doc claimed the right to let it. The
    /// heuristics that tried for truth were measured and dropped: flagging a
    /// section that claims something is both missing and done scored 23 hits
    /// before the 104/105 correction and 23 after, because it keys on tense
    /// rather than fact.
    /// ⚠️ Each pattern names the DOCUMENT it licenses, because the bare words
    /// are ordinary technical vocabulary here — `design.md` describes a Key
    /// Transparency log as append-only, which is correct and unrelated. A ban
    /// on the word alone went red on that paragraph the first time it ran.
    final banned = <RegExp, String>{
      RegExp(r'(rulings?|entries|the ledger|this (doc|file|section))\s+'
              r'(are|is)\s+append-only',
          caseSensitive: false):
          'a ledger whose rulings are "append-only" cannot be corrected, so '
              'every falsified claim stays and the heading becomes the stalest '
              'line in the file',
      // "left as written" is deliberately NOT banned. Measured against the doc
      // set it hit three passages, all three legitimate: each keeps superseded
      // prose *and* carries a dated banner naming what closed, which is the
      // opposite of licensing rot. A pattern wrong on every occurrence in the
      // corpus does not earn a place here.
      RegExp(r'(is|are|was|were) left alone because', caseSensitive: false):
          'the reason is always a structural cost — links to sweep, a body to '
              're-read — and correctness outranks it',
    };

    /// An occurrence is allowed when the same paragraph records that the rule
    /// was overruled: `detail/` keeps the history of decisions this project
    /// reversed, and deleting that is its own kind of dishonesty.
    bool isHistorical(String text, int at) =>
        text.substring(at, (at + 260).clamp(0, text.length)).contains('overruled');

    test('no doc carries a rule permitting stale prose', () {
      final offences = <String>[];
      for (final file in [..._ceilings.keys, 'detail/decisions.md',
        'detail/implementation-plan.md']) {
        final text = _read(file);
        for (final entry in banned.entries) {
          for (final m in entry.key.allMatches(text)) {
            if (isHistorical(text, m.start)) continue;
            offences.add('$file: "${m.group(0)}" — ${entry.value}');
          }
        }
      }
      expect(offences, isEmpty,
          reason: 'correct the claim instead, and the heading above it. A '
              'genuinely historical mention must say in the same paragraph '
              'that the rule was overruled:\n${offences.join('\n')}');
    });

    test('the ledger states that a heading tracks the current outcome', () {
      // The conventions this whole group defends. If the sentence goes, the
      // group is guarding a rule nobody is told about.
      final index = _read('decisions.md');
      expect(index, contains('Ruling numbers are permanent; headings are not.'),
          reason: 'decisions.md must keep saying that a heading states what '
              'the ruling means now. Ruling 104 sat under a heading claiming '
              'the opposite of its outcome because a doc said the heading was '
              'fixed by its inbound links');
      expect(index, contains('Correct in place; do not append.'),
          reason: 'decisions.md must keep the rule that a falsified claim is '
              'replaced rather than layered over');
    });
  });
}
