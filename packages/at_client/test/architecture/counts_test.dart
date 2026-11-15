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

  test('a result is read as a number, a tally or a list of hits', () {
    expect(_tally(''), 0);
    expect(_tally('5\n'), 5);
    expect(_tally('      3 at_client\n      2 at_auth\n'), 5);
    expect(_tally('packages/a/lib/x.dart:16:  foo\n'), 1);
    expect(_tally('a.dart\nb.dart\n'), 2);
  });

  test('every count on the page reproduces', () {
    expect(counts.length, greaterThanOrEqualTo(20),
        reason: 'the parser must reach every command on the page');
    final risen = <String>[];
    for (final count in counts) {
      final result = Process.runSync('bash', ['-c', count.command],
          workingDirectory: root, environment: {'W': workspace});
      expect(result.exitCode, anyOf(0, 1),
          reason: '${count.label}: ${result.stderr}');
      final found = _tally(result.stdout as String);
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
  final line = RegExp(r'^- (.+?): `(git .+?)` gives (\d+)', multiLine: true);
  return (
    workspace: workspace,
    counts: [
      for (final m in line.allMatches(section))
        _Count(m.group(1)!, m.group(2)!, int.parse(m.group(3)!)),
    ],
  );
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
