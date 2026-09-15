/// Guards the allowlist in `dart_test.yaml`: every `*_test.dart` under `test/`
/// must be either allowlisted or under `test/pq/`, and nothing may be both.
///
/// The allowlist keeps post-quantum writes off the long-lived @ce2e atSigns;
/// this file catches the other direction, where a test nobody adds to the list
/// silently never runs and so looks exactly like a test that passes.
///
/// Pure local file inspection; it talks to no atServer.
library;

import 'dart:io';

import 'package:test/test.dart';

/// The paths `dart_test.yaml` allows a bare `dart test` to run.
///
/// Parsed as text rather than with a YAML library, so this reads what the
/// runner reads.
Set<String> _allowlist(File config) {
  final lines = config.readAsLinesSync();
  final start = lines.indexWhere((l) => l.trimRight() == 'paths:');
  if (start < 0) {
    fail('${config.path} has no `paths:` block — the allowlist that keeps '
        'post-quantum tests away from the long-lived atSigns is gone');
  }
  final paths = <String>{};
  for (final line in lines.skip(start + 1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (!trimmed.startsWith('- ')) break;
    paths.add(trimmed.substring(2).trim());
  }
  return paths;
}

void main() {
  final config = File('dart_test.yaml');
  final testDir = Directory('test');

  late Set<String> allowlisted;
  late List<String> discovered;

  setUpAll(() {
    expect(config.existsSync(), isTrue,
        reason: 'cwd is ${Directory.current.path}; dart_test.yaml must be '
            'readable from the package root the runner starts in');
    allowlisted = _allowlist(config);
    discovered = testDir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('_test.dart'))
        .toList()
      ..sort();
  });

  test('every test file is either allowlisted or under test/pq/', () {
    final unclassified = discovered
        .where((p) => !allowlisted.contains(p) && !p.startsWith('test/pq/'))
        .toList();
    expect(unclassified, isEmpty,
        reason: 'these test files run nowhere: not listed in dart_test.yaml '
            'and not under test/pq/. Add each to the allowlist if it is safe '
            'against the long-lived @ce2e atSigns, or move it to test/pq/ if '
            'it writes post-quantum material');
  });

  test('nothing under test/pq/ is allowlisted', () {
    final leaked = allowlisted.where((p) => p.startsWith('test/pq/')).toList();
    expect(leaked, isEmpty,
        reason: 'allowlisting a test/pq/ file puts post-quantum writes back '
            'on @ce2e1..@ce2e4, where a signing root can never be rewritten');
  });

  test('every allowlisted path exists', () {
    final missing = allowlisted.where((p) => !File(p).existsSync()).toList();
    expect(missing, isEmpty,
        reason: 'dart_test.yaml names files that are not there — the runner '
            'fails the whole run on these, so fix the list');
  });

  test('every test under test/pq/ carries the pq tag', () {
    // A file may legitimately carry a second tag beside `pq`, so match a Tags
    // annotation containing it rather than the literal `@Tags(['pq'])`.
    final tagsWithPq =
        RegExp(r"@Tags\(\s*\[[^\]]*'pq'[^\]]*\]\s*\)", multiLine: true);
    final untagged = discovered
        .where((p) => p.startsWith('test/pq/'))
        .where((p) => !tagsWithPq.hasMatch(File(p).readAsStringSync()))
        .toList();
    expect(untagged, isEmpty,
        reason: 'the directory is what keeps these off the long-lived '
            'atSigns, but the tag is what makes `dart test test -x pq` mean '
            'the same thing — keep them in step');
  });
}
