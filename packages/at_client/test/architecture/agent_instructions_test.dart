import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _reason = 'AGENTS.md holds the agent instructions in full, and every '
    'level-two section of .github/copilot-instructions.md is a copy of the '
    'AGENTS.md section with the same heading; text only Copilot needs goes '
    'above its first heading. A section the two share is changed in both, in '
    "one PR, with a code owner's review (.github/CODEOWNERS).";

/// Every level-two section of `.github/copilot-instructions.md` is a copy of
/// the `AGENTS.md` section with the same heading, so the two cannot drift
/// apart.
void main() {
  late Map<String, String> agents;
  late Map<String, String> copilot;

  setUpAll(() async {
    final barrel = await Isolate.resolvePackageUri(
        Uri.parse('package:at_client/at_client.dart'));
    final root =
        p.dirname(p.dirname(p.dirname(p.dirname(barrel!.toFilePath()))));
    agents = _sections(File(p.join(root, 'AGENTS.md')).readAsStringSync());
    copilot = _sections(File(p.join(root, '.github', 'copilot-instructions.md'))
        .readAsStringSync());
  });

  test('the section parser splits on level-two headings', () {
    expect(_sections('# Title\nintro\n## A\none\n\n## B\ntwo\n### C\nthree\n'),
        {'A': 'one', 'B': 'two\n### C\nthree'});
  });

  test('Copilot carries the architecture rules and the review questions', () {
    expect(
        copilot.keys,
        containsAll([
          'Architecture rules come first',
          'Use the mechanism that exists',
          'When you review',
        ]));
  });

  test('a Copilot section that differs or that AGENTS.md lacks is drift', () {
    expect(_drift({'A': 'one', 'C': 'three'}, {'A': 'uno', 'B': 'two'}), [
      '"A" differs from AGENTS.md',
      '"B" is not a section of AGENTS.md',
    ]);
  });

  test('every section Copilot repeats matches AGENTS.md', () {
    expect(_drift(agents, copilot), isEmpty, reason: _reason);
  });
}

/// Each section of [copilot] that is missing from [agents], or differs from
/// the section of the same heading there.
List<String> _drift(Map<String, String> agents, Map<String, String> copilot) {
  return [
    for (final MapEntry(key: heading, value: body) in copilot.entries)
      if (!agents.containsKey(heading))
        '"$heading" is not a section of AGENTS.md'
      else if (body != agents[heading])
        '"$heading" differs from AGENTS.md',
  ];
}

/// The body under each `## ` heading in [markdown], trimmed.
Map<String, String> _sections(String markdown) {
  final heading = RegExp(r'^## (.+)$', multiLine: true);
  final matches = heading.allMatches(markdown).toList();
  return {
    for (var i = 0; i < matches.length; i++)
      matches[i].group(1)!.trim(): markdown
          .substring(matches[i].end,
              i + 1 < matches.length ? matches[i + 1].start : markdown.length)
          .trim(),
  };
}
