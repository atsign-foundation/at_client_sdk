@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every file `lib/<entry>` exports, transitively.
Set<String> _exported(String entry, [Set<String>? seen]) {
  final files = seen ?? <String>{};
  final file = File('lib/$entry');
  if (!files.add(entry)) return files;
  final directive = RegExp(r"^export '([^']+)'", multiLine: true);
  final dir =
      entry.contains('/') ? entry.substring(0, entry.lastIndexOf('/')) : '';
  for (final m in directive.allMatches(file.readAsStringSync())) {
    final path = m.group(1)!;
    if (path.startsWith('package:')) continue;
    _exported(dir.isEmpty ? path : '$dir/$path', files);
  }
  return files;
}

void main() {
  final files = _exported('at_client_wasm_web.dart');
  final sources = {
    for (final f in files) f: File('lib/$f').readAsStringSync(),
  };

  test('exports the passkey entry points', () {
    final entry = sources.entries
        .where((e) => e.key.endsWith('web_passkey_entry.dart'))
        .single
        .value;
    for (final name in ['onboardNewAtSign', 'passkeyLogin', 'prfSupported']) {
      expect(entry, contains('$name('));
    }
  });

  test('exports the setup lock timeout', () {
    final barrel = File('lib/at_client_wasm_web.dart').readAsStringSync();
    expect(
        barrel,
        matches(RegExp(
            r"^export '[^']*web_setup_lock\.dart' show[^;]*\bSetupLockTimeoutException\b",
            multiLine: true)));
  });

  test('no exported file carries a test seam', () {
    for (final MapEntry(:key, :value) in sources.entries) {
      expect(value, isNot(contains('visibleForTesting')), reason: key);
    }
  });

  test('no exported file is a fake or a test double', () {
    for (final f in files) {
      expect(f, isNot(matches(RegExp(r'fake|_fakes|testing'))), reason: f);
    }
    expect(files, isNot(contains('src/session/passkey_session.dart')),
        reason: 'the seam-taking core stays internal');
    expect(files, isNot(contains('src/session/session_open.dart')));
  });
}
