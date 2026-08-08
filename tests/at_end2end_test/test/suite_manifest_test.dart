/// Guards the allowlist in `dart_test.yaml`.
///
/// This suite runs against LONG-LIVED atSigns (@ce2e1..@ce2e4 on
/// root.atsign.wtf), so `dart_test.yaml` names the files a bare `dart test`
/// may run rather than excluding the ones it may not. That direction is what
/// keeps a forgotten convention harmless: an unlisted test does not run.
///
/// Its one weakness is the other direction — a new NON-post-quantum test that
/// nobody adds to the list would silently never run, and a test that never
/// runs looks exactly like a test that passes. This file closes that: every
/// `*_test.dart` under `test/` must be either allowlisted or under `test/pq/`,
/// and nothing may be both.
///
/// Pure local file inspection; it talks to no atServer.
library;

import 'dart:io';

import 'package:test/test.dart';

/// The paths `dart_test.yaml` allows a bare `dart test` to run.
///
/// Parsed as text rather than through a YAML library: the whole point is to
/// read what the runner reads, and the `paths:` block is a flat list of
/// scalars.
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
    if (!trimmed.startsWith('- ')) break; // end of the block
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
    // `dart test` runs from the package root, so these relative paths resolve
    // the same way the runner's own `paths:` entries do.
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
    final untagged = discovered
        .where((p) => p.startsWith('test/pq/'))
        .where((p) => !File(p).readAsStringSync().contains("@Tags(['pq'])"))
        .toList();
    expect(untagged, isEmpty,
        reason: 'the directory is what keeps these off the long-lived '
            'atSigns, but the tag is what makes `dart test test -x pq` mean '
            'the same thing — keep them in step');
  });
}
