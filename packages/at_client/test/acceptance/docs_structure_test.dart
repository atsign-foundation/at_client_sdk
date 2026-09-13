/// Guards the shape of the PQ doc set, which is a structure rather than a
/// convention.
///
/// The set is split in two: six **live** files carrying only what is current,
/// and `detail/` carrying every ruling body and every completed or parked plan
/// item, so that reading or grepping a live file cannot drag a rejected design
/// into view.
///
/// ⚠️ **Only the structural rules are assertable.** Nothing here can tell
/// whether a paragraph is true, so these rails go red for a broken link or a
/// missing row and stay green for a sentence the tree has falsified.
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

/// The anchors GitHub actually offers for [markdown]: every heading's slug,
/// with a repeated slug suffixed `-1`, `-2` in order of appearance, which is
/// how a link to the second "The ruling" under a numbered section resolves.
/// [_headingSlugs] collapses repeats and is right for the checks that want
/// the set of distinct headings; this one is right for resolving links.
Set<String> _anchorSlugs(String markdown) {
  final seen = <String, int>{};
  final anchors = <String>{};
  for (final m
      in RegExp(r'^#{1,6}\s+(.*?)\s*$', multiLine: true).allMatches(markdown)) {
    final slug = _slug(m.group(1)!);
    final n = seen.update(slug, (v) => v + 1, ifAbsent: () => 0);
    anchors.add(n == 0 ? slug : '$slug-$n');
  }
  return anchors;
}

/// Strips fenced blocks and then code spans, because a `](target)` inside
/// either is a quotation of link syntax rather than a link — the PQ detail
/// files describe past link repairs in exactly that form.
String _withoutCode(String s) =>
    _withoutCodeSpans(s.replaceAll(RegExp(r'```.*?```', dotAll: true), ''));

/// The Markdown files under `docs/` that git tracks, so a gitignored draft
/// present in one checkout cannot redden the rail there and nowhere else.
List<File> _trackedDocs() {
  final root = repoRoot();
  final ls =
      Process.runSync('git', ['-C', root.path, 'ls-files', '--', 'docs']);
  if (ls.exitCode != 0) {
    throw StateError('git ls-files failed: ${ls.stderr}');
  }
  return (ls.stdout as String)
      .split('\n')
      .where((p) => p.endsWith('.md'))
      .map((p) => File('${root.path}/$p'))
      .toList();
}

const _liveFiles = <String>[
  'decisions.md',
  'implementation-plan.md',
  'acceptance.md',
  'design.md',
  'roadmap.md',
  'seal-spec.md',
];

/// Strips code spans, because a status marker inside one is a CITATION of a
/// past status rather than a status — a checker that counts the quotation
/// reports the defect it has just fixed.
String _withoutCodeSpans(String s) => s.replaceAll(RegExp(r'`[^`]*`'), '');

void main() {
  group('no LINKED heading is duplicated', () {
    // NOTE: [_headingSlugs] returns a Set, so a heading written twice in one
    // file collapses and every other check here passes. GitHub resolves a
    // duplicated anchor to the FIRST occurrence and suffixes the rest, so the
    // second copy is unreachable.
    //
    // Scoped to slugs something actually LINKS to: a bare duplicate is
    // harmless, and the ledger legitimately repeats sub-headings like
    // "The ruling" under many rulings.
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

  group('every link in the doc set resolves', () {
    // A heading renamed in one file breaks links from every other silently;
    // this is the check that reads the target. Links to the web are not
    // resolved, and a target inside a code span or a fence is prose about a
    // link rather than one.
    test('every relative link reaches a file, and every anchor a heading', () {
      final docs = _trackedDocs();
      final anchorsOf = <String, Set<String>>{};
      final broken = <String>[];
      var checked = 0;
      for (final doc in docs) {
        final lines = _withoutCode(doc.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          for (final m in RegExp(r'\]\(([^)\s]+)\)').allMatches(lines[i])) {
            final target = m.group(1)!;
            if (target.startsWith('http') || target.startsWith('mailto:')) {
              continue;
            }
            checked++;
            final hash = target.indexOf('#');
            final path = hash < 0 ? target : target.substring(0, hash);
            final anchor = hash < 0 ? '' : target.substring(hash + 1);
            final file = path.isEmpty
                ? doc
                : File(
                    Uri.file(doc.parent.path + '/').resolve(path).toFilePath());
            final where = '${doc.path.substring(repoRoot().path.length + 1)}:'
                '${i + 1} -> $target';
            final kind = FileSystemEntity.typeSync(file.path);
            if (kind == FileSystemEntityType.notFound) {
              broken.add('$where (no such file)');
              continue;
            }
            // A directory link renders as a listing and carries no headings.
            if (anchor.isEmpty || kind == FileSystemEntityType.directory) {
              continue;
            }
            final anchors = anchorsOf.putIfAbsent(
                file.path, () => _anchorSlugs(file.readAsStringSync()));
            if (!anchors.contains(anchor)) {
              broken.add('$where (no such heading)');
            }
          }
        }
      }
      expect(docs, isNotEmpty, reason: 'git ls-files found no docs');
      expect(checked, greaterThan(100),
          reason: 'only $checked links found across ${docs.length} docs, so '
              'the link pattern is not matching what the docs write');
      expect(broken, isEmpty,
          reason: 'a link reaches nothing. Renamed heading: update every '
              'link to it (grep the old slug). Moved or deleted file: repoint '
              'or unlink; a name kept as plain text loses nothing. A target '
              'outside this repository is broken for everyone but its author.'
              '\n  ${broken.join('\n  ')}');
    });
  });

  group('every table row has its header\'s cell count', () {
    // A row with the wrong count still RENDERS, with its content in the wrong
    // column or silently dropped past the header, so nothing but a count sees
    // it. An unescaped `|` inside a code span splits the cell too; `\|` does
    // not. A one-cell row is a deliberate band or caption and is exempt.
    test('no table row is malformed', () {
      final docs = _trackedDocs();
      int cells(String line) => RegExp(r'(?<!\\)\|').allMatches(line).length;
      final malformed = <String>[];
      var rows = 0;
      for (final doc in docs) {
        final lines = doc.readAsStringSync().split('\n');
        final where = doc.path.substring(repoRoot().path.length + 1);
        var i = 0;
        while (i < lines.length) {
          final isHeader = lines[i].startsWith('|') &&
              i + 1 < lines.length &&
              RegExp(r'^\|\s*:?-{2,}').hasMatch(lines[i + 1]);
          if (!isHeader) {
            i++;
            continue;
          }
          final expected = cells(lines[i]);
          i += 2;
          while (i < lines.length && lines[i].startsWith('|')) {
            rows++;
            final n = cells(lines[i]);
            if (n != expected && n != 2) {
              malformed.add('$where:${i + 1} has ${n - 1} cells, header has '
                  '${expected - 1}');
            }
            i++;
          }
        }
      }
      expect(rows, greaterThan(100),
          reason: 'only $rows table rows found across ${docs.length} docs, so '
              'the table pattern is not matching what the docs write');
      expect(malformed, isEmpty,
          reason: 'a table row does not match its header. Rebuild the row '
              'from its cells rather than appending to it, and escape any '
              'literal pipe as \\|, code spans included:'
              '\n  ${malformed.join('\n  ')}');
    });
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
      // sub-rulings were changed later, on the date given".
      final index = _read('decisions.md');
      // NOTE: `[ \t]`, never `\s` — `\s` eats the newline, so each match
      // swallows the following row and the count silently halves.
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
    // The id shape comes from manifest.dart, so widening the catalogue to a
    // new cluster is one edit.
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
    // The check is deliberately one-directional: a section with no done marker
    // is not evidence of anything, so only "row says owed, body says done" is
    // a failure. On an intended change, delete the row — do not soften the
    // body.
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

    // The rows in the P0-P3 bands name no section, so the check above never
    // sees them; a done marker inside such a row's own cells is the same
    // defect. On 2026-09-11 a P1 row sat for two days with ✅ DONE in its
    // cell, invisible from the heading, and two rows were inserted beside it.
    test('no TODO row carries a done marker in its own cells', () {
      final plan = _read('implementation-plan.md');
      final todoStart = plan.indexOf('\n## TODO\n') + '\n## TODO\n'.length;
      expect(todoStart, greaterThan(0), reason: 'the TODO table did not parse');
      final rest = plan.substring(todoStart);
      final todo = rest.substring(0, rest.indexOf('\n## '));

      final rows = RegExp(r'^\| \*\*(.+?)\*\*.*$', multiLine: true)
          .allMatches(todo)
          .toList();
      expect(rows, isNotEmpty, reason: 'no bold-titled TODO rows parsed');

      final done = RegExp(r'✅|\bDONE\b|\bCOMPLETE\b|\bCLOSED\b');
      final wrong = <String>[];
      for (final row in rows) {
        final hit = done.firstMatch(_withoutCodeSpans(row.group(0)!));
        if (hit != null) {
          wrong.add('"${row.group(1)}" carries "${hit.group(0)}"');
        }
      }
      expect(wrong, isEmpty,
          reason: 'a TODO row says, in its own cells, that something is done. '
              'If the whole item is done, DELETE the row. If half is done, '
              'reword the row to name only what is still owed - the done half '
              'is in git log - so the heading says what the cell says:'
              '\n  ${wrong.join('\n  ')}');
    });
  });

  group('the plan and the catalogue agree about what is done', () {
    /// Every line of both plan files, each entry `<file>\u0000<line>`.
    ///
    /// ⚠️ The NUL is written as an ESCAPE, never a raw byte: a literal
    /// NUL makes the whole file `data` to `file(1)`, so `grep` prints nothing
    /// and exits 1 while `git grep` still reads it.
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
    /// describing one document's history — a doc saying rulings are
    /// append-only pre-authorises the next stale paragraph.
    ///
    /// ⚠️ Each pattern must name the DOCUMENT it licenses: the bare words
    /// are ordinary technical vocabulary here, and a Key Transparency log is
    /// legitimately append-only.
    final banned = <RegExp, String>{
      RegExp(
              r'(rulings?|entries|the ledger|this (doc|file|section))\s+'
              r'(are|is)\s+append-only',
              caseSensitive: false):
          'a ledger whose rulings are "append-only" cannot be corrected, so '
              'every falsified claim stays and the heading becomes the stalest '
              'line in the file',
      // "left as written" is deliberately NOT banned: every occurrence in the
      // doc set keeps superseded prose beside a dated banner naming what closed
      // it, which is the opposite of licensing rot.
      RegExp(r'(is|are|was|were) left alone because', caseSensitive: false):
          'the reason is always a structural cost — links to sweep, a body to '
              're-read — and correctness outranks it',
    };

    /// Whether the paragraph at [at] records that the rule was overruled, which
    /// makes the occurrence a historical note rather than a live licence.
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
    // NOTE: nothing but the ledger's clause level reads THEN clauses out of the
    // catalogue, so prose moving to a form the parser does not recognise makes
    // every row report 0/0 — a ledger that has stopped measuring reads as one
    // with nothing left to prove.
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
    // A test no doc names is work the next reader rebuilds, and a filename is
    // the cheapest thing to check.
    /// Every Markdown file in the PQ doc set, concatenated.
    ///
    /// Read once per test rather than hoisted, so a run selecting neither rail
    /// does not build it.
    String docSet() => _pq()
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    test('each pq_*_test.dart is named somewhere under docs/projects/pq', () {
      // Both roots: a `pq_*` file is no less rebuildable for living in a
      // package's own test tree, beside the code it tests.
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
      // measuring nothing.
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
      // The sharper half of the rail above, reaching files no filename
      // convention would catch: a cited test is PQ-relevant by construction —
      // a row leans on it for its verdict — while the status table names only
      // the acceptance SCENARIO file, so the test actually carrying the proof
      // appears nowhere a reader looks.
      final cited = citedTestPaths();

      expect(cited.length, greaterThanOrEqualTo(60),
          reason: 'the acceptance sources named 81 distinct files on '
              '2026-08-28. A sharp drop means this parse stopped finding '
              'them, not that the citations went away');

      // Settled here so a vanished file is reported as a vanished file: this
      // rail reads the sources rather than a run, and without the check a
      // deleted test surfaces below as "no document names it".
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
