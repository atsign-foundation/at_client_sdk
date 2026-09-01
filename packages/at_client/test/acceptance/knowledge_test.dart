/// Guards the citations in `docs/knowledge/`.
///
/// A nugget is a fact somebody paid for once, written down so nobody pays
/// again. Its value is entirely in the `Evidence` line, and evidence rots
/// silently: the code moves, the citation goes on looking authoritative, and a
/// reader spends the hour the nugget existed to save.
///
/// So the format cites a **pattern**, not a line number, and this file asserts
/// the pattern still matches. The reason is asymmetric failure rather than
/// decay rates — a path that rots stops resolving and says so, while a line
/// number that rots usually keeps resolving and points at something unrelated,
/// which reads as verified while being wrong. A pattern has nothing to drift
/// to: it re-derives the location on every run and goes empty when the code
/// changes.
///
/// ⚠️ **This cannot tell whether a nugget is TRUE.** It checks that the
/// evidence still says what it said. A nugget whose claim the tree falsified
/// stays green here, exactly as `docs_structure_test.dart` stays green for a
/// false paragraph.
///
/// ⛔ **Every count below is asserted non-empty before it is used.** An empty
/// corpus reports "0 broken citations" and reads precisely like a clean pass;
/// a stray path or a changed heading is all it takes.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'manifest.dart';

Directory _knowledge() => Directory('${repoRoot().path}/docs/knowledge');

/// `- \`repo\` -> \`path\` -> \`pattern\`` with an optional trailing `xN`.
///
/// The pattern is a literal substring. It is captured lazily up to the last
/// backtick on the line so a pattern may itself contain `->`.
final RegExp _citation = RegExp(
  r'^-\s+`([^`]+)`\s*->\s*`([^`]+)`\s*->\s*`(.+)`(?:\s+x(\d+))?\s*$',
);

class _Citation {
  _Citation(this.repo, this.path, this.pattern, this.expected, this.source);

  /// `.` for this repo, or `<name>@<ref>` for a sibling.
  final String repo;
  final String path;
  final String pattern;

  /// Exact count required, or null for "at least one".
  final int? expected;

  /// The nugget file the citation was read from, for failure messages.
  final String source;

  bool get isLocal => repo == '.';
  String get siblingName => repo.split('@').first;
  String get siblingRef => repo.split('@').last;

  @override
  String toString() => '$repo -> $path -> "$pattern"';
}

List<File> _nuggetFiles() => _knowledge()
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.md') && !f.path.endsWith('README.md'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

List<_Citation> _citationsOf(File f) {
  final out = <_Citation>[];
  for (final line in f.readAsLinesSync()) {
    final m = _citation.firstMatch(line);
    if (m == null) continue;
    out.add(_Citation(
      m.group(1)!,
      m.group(2)!,
      m.group(3)!,
      m.group(4) == null ? null : int.parse(m.group(4)!),
      f.uri.pathSegments.last,
    ));
  }
  return out;
}

/// The file's contents, or null when it cannot be read.
///
/// A sibling is read at the ref the nugget NAMES, never from its working tree
/// — a sibling checkout is usually on its own branch, so reading the file on
/// disk would answer a question nobody asked.
String? _contents(_Citation c) {
  if (c.isLocal) {
    final f = File('${repoRoot().path}/${c.path}');
    return f.existsSync() ? f.readAsStringSync() : null;
  }
  final sibling = Directory('${repoRoot().parent.path}/${c.siblingName}');
  if (!sibling.existsSync()) return null;
  final r = Process.runSync(
    'git',
    ['-C', sibling.path, 'show', '${c.siblingRef}:${c.path}'],
  );
  return r.exitCode == 0 ? r.stdout as String : null;
}

int _countOf(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

void main() {
  final files = _nuggetFiles();
  final citations = [for (final f in files) ..._citationsOf(f)];

  group('the knowledge base has something to guard', () {
    test('there is at least one nugget file', () {
      expect(files, isNotEmpty,
          reason: 'docs/knowledge holds no nugget file, so every assertion '
              'below would pass by having nothing to check');
    });

    test('every nugget file carries at least one citation', () {
      for (final f in files) {
        expect(_citationsOf(f), isNotEmpty,
            reason: '${f.path} has no parseable Evidence citation. Either it '
                'has none, or the format drifted from the one README.md '
                'specifies — both are defects, and both look like a pass');
      }
    });

    test('at least one citation is LOCAL, so the rail is never all-skips', () {
      expect(citations.where((c) => c.isLocal), isNotEmpty,
          reason: 'every citation names a sibling repo, so on a machine '
              'without those checkouts this rail checks nothing while '
              'reporting green');
    });
  });

  group('every cited pattern still matches', () {
    test('local citations', () {
      final failures = <String>[];
      var checked = 0;
      for (final c in citations.where((c) => c.isLocal)) {
        final body = _contents(c);
        if (body == null) {
          failures.add('${c.source}: ${c.path} does not exist ($c)');
          continue;
        }
        checked++;
        final n = _countOf(body, c.pattern);
        final want = c.expected;
        if (want == null && n == 0) {
          failures.add('${c.source}: no match for "${c.pattern}" in ${c.path}');
        } else if (want != null && n != want) {
          failures.add('${c.source}: "${c.pattern}" in ${c.path} matched $n '
              'time(s), the nugget says x$want');
        }
      }
      expect(checked, greaterThan(0),
          reason: 'no local citation was read, so the emptiness of `failures` '
              'says nothing');
      expect(failures, isEmpty,
          reason: 'a citation no longer matches. Re-derive it and amend the '
              'nugget — or, if the fact itself changed, rewrite the nugget:\n'
              '${failures.join('\n')}');
    });

    test('sibling-repo citations, read at the ref each nugget names', () {
      final failures = <String>[];
      final skipped = <String>[];
      for (final c in citations.where((c) => !c.isLocal)) {
        final body = _contents(c);
        if (body == null) {
          skipped.add('$c');
          continue;
        }
        final n = _countOf(body, c.pattern);
        final want = c.expected;
        if (want == null && n == 0) {
          failures.add('${c.source}: no match for "${c.pattern}" in '
              '${c.repo} ${c.path}');
        } else if (want != null && n != want) {
          failures.add('${c.source}: "${c.pattern}" in ${c.repo} ${c.path} '
              'matched $n time(s), the nugget says x$want');
        }
      }
      // Printed rather than swallowed: a skip is a gap in coverage, and a
      // silent one is indistinguishable from a pass.
      if (skipped.isNotEmpty) {
        printOnFailure('skipped ${skipped.length} sibling citation(s) — '
            'checkout absent or ref unavailable:\n  ${skipped.join('\n  ')}');
        stdout.writeln('KNOWLEDGE  skipped ${skipped.length} sibling '
            'citation(s): checkout absent or ref unavailable');
      }
      expect(failures, isEmpty,
          reason: 'a citation into a sibling repo no longer matches at the ref '
              'the nugget names:\n${failures.join('\n')}');
    });
  });

  group('the format README specifies is the one in use', () {
    test('no nugget still cites a bare line number', () {
      final offenders = <String>[];
      final lineRef = RegExp(r'`[^`]+\.(dart|sh|yaml|md|Dockerfile):\d+');
      for (final f in files) {
        for (final line in f.readAsLinesSync()) {
          if (!line.startsWith('**Evidence:**') && !line.startsWith('- ')) {
            continue;
          }
          if (lineRef.hasMatch(line)) {
            offenders.add('${f.uri.pathSegments.last}: $line');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'Evidence cites a pattern, not a coordinate (README.md, '
              '"Evidence cites a PATTERN, not a line number"). A line number '
              'that rots keeps resolving and points somewhere else:\n'
              '${offenders.join('\n')}');
    });

    test('every citation names a ref for a sibling repo', () {
      for (final c in citations.where((c) => !c.isLocal)) {
        expect(c.repo, contains('@'),
            reason: 'citation "$c" in ${c.source} names a sibling repo with no '
                'ref. Reading a sibling working tree is a claim about whatever '
                'branch it happens to be on');
      }
    });
  });
}
