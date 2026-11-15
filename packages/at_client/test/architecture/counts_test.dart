@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _reason = 'docs/architecture/invariants.md: an exception count may only '
    'fall. Use the mechanism the rule names instead of adding another '
    "exception. Raising a count needs a code owner's review "
    '(.github/CODEOWNERS), in a PR of its own ahead of the change that needs '
    'it.';

/// The commands under "How the counts were made" in
/// docs/architecture/invariants.md, each with the number the page quotes. The
/// page is the pin: a count that rises above it fails here.
void main() {
  late String root;
  late String workspace;
  late List<_Count> counts;

  setUpAll(() async {
    final barrel = await Isolate.resolvePackageUri(
        Uri.parse('package:at_client/at_client.dart'));
    root = p.dirname(p.dirname(p.dirname(p.dirname(barrel!.toFilePath()))));
    final page = File(p.join(root, 'docs', 'architecture', 'invariants.md'))
        .readAsStringSync();
    (workspace: workspace, counts: counts) = _parse(page);
  });

  test('the parser reads a count line and the workspace list', () {
    final parsed = _parse('## How the counts were made\n\n'
        '```sh\nW="packages/a/lib packages/b/lib"\n```\n\n'
        "- A9, things, by package: `git grep -n 'x' -- \$W | wc -l` gives 7: "
        '`a` 7.\n');
    expect(parsed.workspace, 'packages/a/lib packages/b/lib');
    expect(parsed.counts.single.label, 'A9, things, by package');
    expect(parsed.counts.single.command, "git grep -n 'x' -- \$W | wc -l");
    expect(parsed.counts.single.quoted, 7);
  });

  test('every bullet in the section is a count line the parser reads', () {
    expect(
        () => _parse('## How the counts were made\n\n'
            '```sh\nW="packages/a/lib"\n```\n\n'
            "- A9, things: `git grep -n 'x' -- \$W | wc -l` gives 7.\n"
            "- A10, others: `git grep -n 'y' -- \$W | wc -l` yields 2.\n"),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('A10, others'))));
  });

  test('a section with no count lines is refused', () {
    expect(
        () => _parse('## How the counts were made\n\n'
            '```sh\nW="packages/a/lib"\n```\n'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('no count lines'))));
  });

  test('a command whose search fails is refused, not counted as 0', () {
    expect(
        () => _run(
            _Count('bad', 'git grep -nP "(" -- \$W 2>/dev/null | wc -l', 0),
            root,
            workspace),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('bad: exit 128'))));
  });

  test('a command that writes to stderr is refused', () {
    expect(
        () => _run(
            _Count(
                'warns',
                "git grep -n 'no''such''text' -- \$W | wc -l; echo oops >&2",
                0),
            root,
            workspace),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('warns: exit 0: oops'))));
  });

  test('a command whose search matches nothing gives 0', () {
    expect(
        _run(_Count('none', "git grep -n 'no''such''text' -- \$W | wc -l", 0),
            root, workspace),
        0);
  });

  test('a result is read as a number, a tally or a list of hits', () {
    expect(_tally(''), 0);
    expect(_tally('5\n'), 5);
    expect(_tally('      3 at_client\n      2 at_auth\n'), 5);
    expect(_tally('packages/a/lib/x.dart:16:  foo\n'), 1);
    expect(_tally('a.dart\nb.dart\n'), 2);
  });

  test('the A5 search finds a platform preset and skips private statics', () {
    final a5 = counts.singleWhere((c) => c.label.startsWith('A5,'));
    final pattern =
        RegExp(r"git grep -nP '([^']+)' --").firstMatch(a5.command)!.group(1)!;
    final dir = Directory.systemTemp.createTempSync('a5_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'preference.dart'))
      ..writeAsStringSync([
        '  factory AtClientPreference.browser() => AtClientPreference._web();',
        '  static final AtClientPreference web = _makeWeb();',
        '  static const int x = 1;',
        '  static String get y => _y;',
        '  static void z() {}',
        '  static List<String> _sealableOrRefuse(List<String> algorithms) {',
        '  static Set<SigningAlgoType> _signableOrRefuse(',
        '  static const _p = 1;',
        '  static String get _q => _y;',
        '  static Map<String, int> _m = {};',
        '  static T gen<T>(T a) => a;',
        '  static T _gen<T>(T a) => a;',
        '  static Map<String, List<int>> _n = {};',
        '',
      ].join('\n'));
    final result = Process.runSync(
        'git', ['grep', '--no-index', '-hnP', pattern, '--', 'preference.dart'],
        workingDirectory: dir.path);
    expect(result.stderr, isEmpty);
    expect(
        (result.stdout as String)
            .trim()
            .split('\n')
            .map((l) => int.parse(l.split(':').first)),
        [1, 2, 3, 4, 5, 11],
        reason: 'A5 in docs/architecture/invariants.md must count every '
            'factory and public static member of AtClientPreference, and no '
            'private static.');
  });

  test('every count on the page reproduces', () {
    final risen = <String>[];
    for (final count in counts) {
      final found = _run(count, root, workspace);
      if (found > count.quoted) {
        risen.add('${count.label}: ${count.quoted} on the page, $found now');
      } else if (found < count.quoted) {
        print('${count.label}: $found, below the ${count.quoted} on the page; '
            'lower the number in docs/architecture/invariants.md.');
      }
    }
    expect(risen, isEmpty, reason: _reason);
  });
}

class _Count {
  final String label;
  final String command;
  final int quoted;

  _Count(this.label, this.command, this.quoted);
}

({String workspace, List<_Count> counts}) _parse(String page) {
  final start = page.indexOf('## How the counts were made');
  if (start < 0) throw StateError('no "How the counts were made" section');
  final section = page.substring(start);
  final workspace =
      RegExp(r'^W="([^"]+)"$', multiLine: true).firstMatch(section)?.group(1);
  if (workspace == null) throw StateError('no W="..." line in the section');
  final line = RegExp(r'^- (.+?): `(git .+?)` gives (\d+)');
  final counts = <_Count>[];
  for (final bullet in section.split('\n').where((l) => l.startsWith('- '))) {
    final m = line.firstMatch(bullet);
    if (m == null) throw StateError('not a count line: $bullet');
    counts.add(_Count(m.group(1)!, m.group(2)!, int.parse(m.group(3)!)));
  }
  if (counts.isEmpty) throw StateError('no count lines in the section');
  return (workspace: workspace, counts: counts);
}

/// The tally of [count]'s command, run under bash with `pipefail`. Exit 1 is
/// a search that matched nothing; a higher exit or any stderr throws, so a
/// broken command is never read as 0.
int _run(_Count count, String root, String workspace) {
  final result = Process.runSync(
      'bash', ['-o', 'pipefail', '-c', count.command],
      workingDirectory: root, environment: {'W': workspace});
  final stderr = (result.stderr as String).trim();
  if (result.exitCode > 1 || stderr.isNotEmpty) {
    throw StateError('${count.label}: exit ${result.exitCode}: $stderr');
  }
  return _tally(result.stdout as String);
}

/// A command's result as one number: a bare number, the sum of a
/// `uniq -c` tally, or else the number of lines it printed.
int _tally(String output) {
  final lines = [
    for (final line in output.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty) return 0;
  if (lines.length == 1 && RegExp(r'^\d+$').hasMatch(lines.single)) {
    return int.parse(lines.single);
  }
  final tally = RegExp(r'^(\d+) \S+$');
  if (lines.every(tally.hasMatch)) {
    return lines.fold(
        0, (sum, line) => sum + int.parse(tally.firstMatch(line)!.group(1)!));
  }
  return lines.length;
}
