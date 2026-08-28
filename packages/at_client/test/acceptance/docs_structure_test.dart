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
/// - the catalogue's status table keeps saying what the scenarios do;
/// - a ruling amended in its body says so in the index;
/// - the plan may not claim DONE for a use case the catalogue has not proven;
/// - no doc licenses itself to leave a falsified claim standing.
///
/// ⚠️ **Correctness outranks every structural rule here, and only the
/// structural ones can be asserted.** Nothing in this file can tell whether a
/// paragraph is true, so the rails go red for a broken link
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

Set<String> _headingSlugs(String markdown) =>
    RegExp(r'^#{1,6}\s+(.*?)\s*$', multiLine: true)
        .allMatches(markdown)
        .map((m) => _slug(m.group(1)!))
        .toSet();

/// The live files.
///
/// These carried per-file line ceilings until 2026-08-17 (gkc). They are gone:
/// a ceiling made *length* the trigger for demotion, when the real trigger is
/// that something has **finished**. The live/detail split is still enforced by
/// the rules below — a ruling body may not sit in the live ledger, an index row
/// must resolve both ways — and those are about correctness, not size.
const _liveFiles = <String>[
  'decisions.md',
  'implementation-plan.md',
  'acceptance.md',
  'design.md',
  'roadmap.md',
  'seal-spec.md',
];

/// A status marker inside a code span is a CITATION of a past status, not a
/// status. Both guards below strip code spans before matching, because the
/// correction for a stale label routinely quotes the label it replaced — and
/// a checker that counts the quotation reports the defect it just fixed. This
/// project has been caught by the code-span version of this before, in an
/// anchor checker.
String _withoutCodeSpans(String s) => s.replaceAll(RegExp(r'`[^`]*`'), '');

void main() {
  group('no LINKED heading is duplicated', () {
    // ⚠️ [_headingSlugs] returns a Set, so a heading written twice in one file
    // collapses and every other check here passes. That is not cosmetic: GitHub
    // resolves a duplicated anchor to the FIRST occurrence and suffixes the
    // rest, so the second copy is unreachable — a demotion that appends a body
    // the file already holds silently orphans it, and a link lands on whichever
    // copy happens to be earlier. Landed 2026-08-17 after a demotion did
    // exactly that to `14.7` and a cold read found it.
    //
    // Scoped to slugs something actually LINKS to. A bare duplicate is
    // harmless, and the ledger legitimately repeats sub-headings like
    // "The ruling" under many rulings — failing on those would demand dozens of
    // indefensible renames, and a rail that fires for an indefensible reason
    // gets deleted rather than obeyed.
    for (final file in [
      ..._liveFiles,
      'detail/acceptance.md',
      'detail/decisions.md',
      'detail/implementation-plan.md',
    ]) {
      test('$file duplicates no slug that is linked', () {
        final headings = RegExp(r'^#{1,6}\s+(.*?)\s*$', multiLine: true)
            .allMatches(_read(file))
            .map((m) => _slug(m.group(1)!))
            .toList();
        final seen = <String>{};
        final duplicated = headings.where((h) => !seen.add(h)).toSet();
        if (duplicated.isEmpty) return;

        // Every anchor referenced anywhere in the doc set, target file
        // unresolved — a slug is "linked" if any document names it. Coarse on
        // purpose: it over-reports rather than missing the case that matters.
        final linked = <String>{};
        for (final f in _pq()
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))) {
          linked.addAll(RegExp(r'\]\([^)]*#([\w-]+)\)')
              .allMatches(f.readAsStringSync())
              .map((m) => m.group(1)!));
        }

        expect(duplicated.intersection(linked), isEmpty,
            reason: 'these slugs appear more than once in $file AND are link '
                'targets, so every link reaches the first copy and the rest '
                'are unreachable. Merge the copies — diff them first, because '
                'the later one is often the fresher');
      });
    }
  });

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
      final bodies =
          _read('detail/decisions.md').split(RegExp(r'^## ', multiLine: true));

      final silent = <String>[];
      for (final body in bodies) {
        final head = RegExp(r'^(\d+[a-z]?)\. ').firstMatch(body);
        if (head == null) continue;
        final dates = amended.allMatches(body).map((m) => m.group(1)!).toList();
        if (dates.isEmpty) continue;
        final st = (status[head.group(1)] ?? '').toUpperCase();
        // A stronger not-in-force status already tells the reader to look.
        if (st.contains('AMENDED') ||
            st.contains('SUPERSEDED') ||
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
    // The id shape comes from manifest.dart so widening the catalogue to a
    // new cluster is one edit. This guard used to spell it out itself, and
    // adding the G cluster reddened it here — a place that reads as unrelated
    // to "the catalogue gained rows".
    final row = RegExp(
        '^\\|\\s*($ucIdPattern)\\s*\\|[^|]*\\|\\s*(\\w[\\w ]*?)\\s*\\|',
        multiLine: true);

    test('every table row is a use case the catalogue defines', () {
      final defined = catalogueUseCases().map((u) => u.id).toSet();
      final rows = row
          .allMatches(_read('acceptance.md'))
          .map((m) => m.group(1)!)
          .toSet();

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
        if (stated != actual)
          wrong.add('$id: table says $stated, tree says $actual');
      }

      expect(wrong, isEmpty,
          reason: 'the status table and the scenarios disagree. The table is '
              'generated from the tree, so the tree wins - regenerate it '
              'rather than editing the row. A hand-maintained status column '
              'is the "current state" table this project has been wrong about '
              'before');
    });
  });

  group('the catalogue summary counts its own table', () {
    /// The headline sentence above `acceptance.md`'s status table.
    ///
    /// The table is generated against the scenarios and cannot drift. This
    /// sentence is prose, and nothing checked it: it read "50 PROVEN · 2
    /// BLOCKED · 1 WITHDRAWN across 53 use cases and 53 scenarios" while the
    /// table under it held 69 rows. The 16-row gap was exactly the UC-G1.x
    /// cluster, added the same day 14.17 landed — a cold read found it, five
    /// sweeps of my own did not, and `catalogue_test.dart` never looked at
    /// this line because it validates the headings instead.
    test('the summary sentence agrees with the table and the scenarios', () {
      final acceptance = _read('acceptance.md');

      final headline = RegExp(
              r'\*\*(\d+) PROVEN · (\d+) BLOCKED · (\d+) WITHDRAWN\*\* across '
              r'(\d+) use cases and (\d+) scenarios')
          .firstMatch(acceptance);
      expect(headline, isNotNull,
          reason: 'the summary sentence did not parse, so this guard checks '
              'nothing — it is the sentence beginning "Today that is"');

      final rows =
          RegExp(r'^\| (UC-[^|]+)\|[^|]*\|\s*(\w+)\s*\|', multiLine: true)
              .allMatches(acceptance)
              .map((m) => m.group(2)!)
              .toList();
      expect(rows, isNotEmpty, reason: 'the status table did not parse');

      int count(String s) => rows.where((r) => r == s).length;
      expect(
        [
          int.parse(headline!.group(1)!),
          int.parse(headline.group(2)!),
          int.parse(headline.group(3)!),
          int.parse(headline.group(4)!),
          int.parse(headline.group(5)!),
        ],
        [
          count('PROVEN'),
          count('BLOCKED'),
          count('WITHDRAWN'),
          rows.length,
          scenarioCount(),
        ],
        reason: 'the summary sentence disagrees with what it summarises. '
            'Derive all five from the table and scenarioCount() — the first '
            'correction to this line got the scenario figure wrong by doing '
            'arithmetic on the sentence it was replacing',
      );
    });
  });

  group('a row that says owed does not point at a section that says done', () {
    /// The one shape a cold read caught and nothing here could.
    ///
    /// 14.17 sat in the TODO table reading "the owed half" for a whole day
    /// while its own section body opened "✅ COMPLETE 2026-08-18", and there
    /// was no DONE row for it either. Every command that counts open work
    /// keys on the ROW, so it counted an item that had shipped — honestly,
    /// which is what makes it dangerous. The plan's own re-derivation warning
    /// names this shape; nothing enforced it.
    ///
    /// The check is deliberately one-directional. A section with no done
    /// marker is not evidence of anything, so only "row says owed, body says
    /// done" is a failure. On an intended change, move the row — do not
    /// soften the body.
    test('no TODO row names a section whose body declares itself done', () {
      final plan = _read('implementation-plan.md');
      final detail = _read('detail/implementation-plan.md');

      final todoStart = plan.indexOf('\n## TODO\n') + '\n## TODO\n'.length;
      expect(todoStart, greaterThan(0), reason: 'the TODO table did not parse');
      final rest = plan.substring(todoStart);
      final todo = rest.substring(0, rest.indexOf('\n## '));

      final rows = RegExp(r'^\| \[(14\.\d+)\]', multiLine: true)
          .allMatches(todo)
          .map((m) => m.group(1)!)
          .toList();
      expect(rows, isNotEmpty,
          reason: 'no TODO rows parsed, so this guard checks nothing — the '
              'probe that first found 14.17 reported zero rows because its '
              'range ended on the heading that opened it');

      final done = RegExp(r'✅|\bDONE\b|\bCOMPLETE\b|\bCLOSED\b');
      final wrong = <String>[];
      for (final id in rows) {
        for (final text in [plan, detail]) {
          final heading =
              RegExp('^#{3,4} ${RegExp.escape(id)}[ \n]', multiLine: true)
                  .firstMatch(text);
          if (heading == null) continue;
          final body = _withoutCodeSpans(text
              .substring(heading.start)
              .split('\n')
              .skip(1)
              .take(5)
              .join(' '));
          final hit = done.firstMatch(body);
          if (hit != null) wrong.add('$id: body opens "${hit.group(0)}"');
        }
      }
      expect(wrong, isEmpty,
          reason: 'a TODO row points at a section that says it is finished. '
              'DELETE the row — the plan records only what is still owed '
              '(gkc, 2026-08-23), and what was done is in the codebase and in '
              'git log. ⚠️ This said "Move the row to DONE" until the DONE '
              'table was removed; there is nowhere to move it to now. If the '
              'row records a rejected proposal or a measurement that closed a '
              'question, that is not "done" — promote it to decisions.md, '
              'because no commit can contain a thing that was never built:'
              '\n  ${wrong.join('\n  ')}');
    });
  });

  group('the plan and the catalogue agree about what is done', () {
    /// The status column in `acceptance.md` is derived from the scenario
    /// files, so it is the one status in the doc set that cannot lie. These
    /// two checks make the plan borrow it.
    ///
    /// ⚠️ **Neither can tell you a use case is MISSING**, which is the failure
    /// that actually happened: the nskey mint election had nine proofs and no
    /// use case, so every rail here was green while the done-bar had never
    /// heard of it. Coverage has no mechanical form. What closes it is the
    /// convention these checks reward — **a plan row marked DONE names the
    /// use cases it proved** — and the more rows that do, the more of the plan
    /// these two actually cover. Today only 6 lines cite one.
    /// Each entry is `<file>\u0000<line>`. NUL is the separator because it
    /// cannot occur in either half, and it is written as an ESCAPE, never as
    /// a raw byte: a literal NUL makes the whole file `data` to `file(1)`, so
    /// `grep` prints nothing and exits 1 over the whole file. `git grep` still
    /// reads it, so the two disagree and the silent one looks like a clean
    /// absence.
    List<String> planLines() => [
          for (final f in const [
            'implementation-plan.md',
            'detail/implementation-plan.md'
          ])
            ..._read(f).split('\n').map((l) => '$f\u0000$l'),
        ];

    final ucId = RegExp(ucIdPattern);

    test('every use case the plan cites is one the catalogue defines', () {
      final defined = catalogueUseCases().map((u) => u.id).toSet();
      final cited = <String>{};
      for (final line in planLines()) {
        cited.addAll(ucId.allMatches(line).map((m) => m.group(0)!));
      }
      expect(cited, isNotEmpty,
          reason: 'the plan cites no use case at all, so this guard checks '
              'nothing — either the plan stopped citing them or the id shape '
              'changed');
      expect(cited.difference(defined), isEmpty,
          reason: 'the plan points at a use case the catalogue does not '
              'define. A renamed or withdrawn use case leaves the plan '
              'claiming a done-bar that no longer exists');
    });

    test('a plan row that claims DONE cites a use case the tree has proven',
        () {
      final status = <String, String>{
        for (final m in RegExp(
                '^\\|\\s*($ucIdPattern)\\s*\\|[^|]*\\|\\s*(\\w[\\w ]*?)\\s*\\|',
                multiLine: true)
            .allMatches(_read('acceptance.md')))
          m.group(1)!: m.group(2)!.trim(),
      };
      expect(status, isNotEmpty, reason: 'the status table did not parse');

      final wrong = <String>[];
      for (final entry in planLines()) {
        final parts = entry.split('\u0000');
        final line = parts[1];
        if (!RegExp(r'\bDONE\b|✅').hasMatch(line)) continue;
        for (final m in ucId.allMatches(line)) {
          final st = status[m.group(0)] ?? '<no row>';
          if (st != 'PROVEN' && st != 'WITHDRAWN') {
            wrong.add('${parts[0]}: a DONE row cites ${m.group(0)}, and the '
                'catalogue says $st');
          }
        }
      }
      expect(wrong, isEmpty,
          reason: 'the plan says done and the done-bar does not:\n'
              '${wrong.join('\n')}');
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
      RegExp(
              r'(rulings?|entries|the ledger|this (doc|file|section))\s+'
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
    bool isHistorical(String text, int at) => text
        .substring(at, (at + 260).clamp(0, text.length))
        .contains('overruled');

    test('no doc carries a rule permitting stale prose', () {
      final offences = <String>[];
      for (final file in [
        ..._liveFiles,
        'detail/acceptance.md',
        'detail/decisions.md',
        'detail/implementation-plan.md'
      ]) {
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

  group('the catalogue states clauses the ledger can count', () {
    // The clause level of the ledger reads THEN clauses out of the catalogue.
    // Nothing else does, so if the prose moves to a form the parser does not
    // recognise, every row silently reports 0/0 — a ledger that has stopped
    // measuring, rendering as one with nothing left to prove. That is the
    // failure this group exists to make loud.
    test('every live row states at least one THEN clause', () {
      final clauses = catalogueClauses();
      final silent = <String>[];
      for (final uc in catalogueUseCases()) {
        if (uc.isWithdrawn) continue;
        if ((clauses[uc.id] ?? const []).isEmpty) silent.add(uc.id);
      }
      expect(silent, isEmpty,
          reason: 'these rows state no THEN clause the parser can see. Either '
              'the row lost its THEN, or it is written in a form '
              '`catalogueClauses` does not recognise — the catalogue uses '
              'both `- **Then:**` bullets and the G1 cluster\'s indented '
              '*Then* / *And*:\n${silent.join(', ')}');
    });

    test('a withdrawn row states none, and that is not a gap', () {
      final clauses = catalogueClauses();
      final withdrawn =
          catalogueUseCases().where((u) => u.isWithdrawn).toList();
      expect(withdrawn, isNotEmpty,
          reason: 'this assertion measures nothing without a withdrawn row to '
              'measure. If the catalogue has none, delete it rather than '
              'letting it pass empty');
      for (final uc in withdrawn) {
        expect(clauses[uc.id], isEmpty,
            reason: '${uc.id} is withdrawn, so it owes no clauses. A parser '
                'finding some here is reading the prose that explains the '
                'withdrawal as though it were a requirement');
      }
    });
  });

  group('every PQ test in the tree is nameable from the doc set', () {
    // A test no doc names is work the next reader rebuilds. Arm 3 of the
    // acceptance suite shipped as
    // `tests/at_functional_test/test/pq_advance_ladder_test.dart` and was
    // named in no project document at all, so the plan went on listing it as
    // owed while it sat green in the tree — and a plan worked top-down
    // rebuilds what it says is owed. A filename is the cheapest thing to
    // check and the one that rots without anything going red.
    /// Every `.md` under docs/projects/pq, concatenated.
    ///
    /// Read once per test rather than hoisted: these two rails are the only
    /// readers, and a shared field would be built even for a run that selects
    /// neither.
    String docSet() => _pq()
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    test('each pq_*_test.dart is named somewhere under docs/projects/pq', () {
      // Both roots. `tests/` alone was the original scope and it left every
      // `pq_*` file in a PACKAGE's own test tree outside the rail — six of
      // them, including `pq_client_bootstrap_test.dart`, which nothing cites
      // and no document named. A file is no less rebuildable for living
      // beside the code it tests.
      final names = <String>{};
      for (final root in ['tests', 'packages']) {
        final dir = Directory('${repoRoot().path}/$root');
        if (!dir.existsSync()) continue;
        names.addAll(dir
            .listSync(recursive: true)
            .whereType<File>()
            // `/test/` in the path, so a `pq_`-prefixed file that is not a
            // test file cannot widen this by accident.
            .where((f) => f.path.contains('${Platform.pathSeparator}test'
                '${Platform.pathSeparator}'))
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.startsWith('pq_') && n.endsWith('_test.dart')));
      }

      // The enumeration is what this rail rests on, so it is asserted rather
      // than assumed: an empty walk satisfies every check below while
      // measuring nothing at all.
      expect(names.length, greaterThanOrEqualTo(14),
          reason: 'the two roots held 19 such files on 2026-08-28 — 14 under '
              'tests/ and 6 under packages/*/test, one name common to both. A '
              'sharp drop means this walk stopped finding them, not that the '
              'tests went away — fix the walk before believing the green');

      final docs = docSet();
      final unnamed = names.where((n) => !docs.contains(n)).toList()..sort();
      expect(unnamed, isEmpty,
          reason: 'name each of these under docs/projects/pq/ — in the '
              'catalogue row it proves, or the plan entry that built it — so '
              'that a reader working the plan top-down cannot rebuild work '
              'that already exists:\n${unnamed.join('\n')}');
    });

    test('every test a citation names is named in the doc set', () {
      // The sharper half of the rail above, and the one that reaches files no
      // filename convention would catch. A cited test is PQ-relevant by
      // construction — a row leans on it for its verdict — while the doc set
      // names only the acceptance SCENARIO file in its status table, so the
      // test actually carrying the proof appears nowhere a reader looks.
      // Measured 2026-08-28: 81 files cited, 74 named, and the seven that
      // were not included one cited by six separate rows and two in
      // packages/at_auth, a package neither this rail nor a widened
      // directory walk had ever looked at.
      final cited = citedTestPaths();

      expect(cited.length, greaterThanOrEqualTo(60),
          reason: 'the acceptance sources named 81 distinct files on '
              '2026-08-28. A sharp drop means this parse stopped finding '
              'them, not that the citations went away');

      // Settled here so a vanished file is reported as a vanished file.
      // provenIn already refuses one while its scenario runs, but this rail
      // reads the sources rather than a run, and without this check a deleted
      // test would surface below as "no document names it" — sending the
      // reader to write a doc line for something that no longer exists.
      final absent = cited
          .where((p) => !File('${repoRoot().path}/$p').existsSync())
          .toList()
        ..sort();
      expect(absent, isEmpty,
          reason: 'cited but not on disk: ${absent.join(', ')}');

      final docs = docSet();
      final unnamed = cited
          .where((p) => !docs.contains(p.split('/').last))
          .toList()
        ..sort();

      expect(unnamed, isEmpty,
          reason: 'a test the catalogue leans on for a verdict, that no '
              'document names, is work the next reader rebuilds — and the '
              'burn-down cannot be audited without being able to find it. '
              'Name each under docs/projects/pq/:\n${unnamed.join('\n')}');
    });
  });
}
