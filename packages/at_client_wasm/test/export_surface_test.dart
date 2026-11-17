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
    final barrel = File('lib/at_client_wasm_web.dart').readAsStringSync();
    expect(
        barrel,
        matches(RegExp(
            r"^export '[^']*web_passkey_entry\.dart'\s+show[^;]*"
            r'\bonboardNewAtSign\b[^;]*\bpasskeyLogin\b[^;]*\bprfSupported\b',
            multiLine: true)));
  });

  test('exports the setup lock timeout', () {
    final barrel = File('lib/at_client_wasm_web.dart').readAsStringSync();
    expect(
        barrel,
        matches(RegExp(
            r"^export '[^']*web_setup_lock\.dart'\s+show[^;]*\bSetupLockTimeoutException\b",
            multiLine: true)));
  });

  test('no exported file carries a test seam', () {
    for (final MapEntry(:key, :value) in sources.entries) {
      expect(value, isNot(contains('visibleForTesting')), reason: key);
    }
  });

  test('exports nothing the core libraries already export', () {
    for (final MapEntry(:key, :value) in sources.entries) {
      expect(
          value,
          isNot(matches(
              RegExp(r"^export 'package:at_(auth|client)/", multiLine: true))),
          reason: key);
    }
    expect(files, isNot(contains('src/session/session_open.dart')));
    expect(files, isNot(contains('src/keys/web_crypto_passkey.dart')));
  });

  test('no exported file is named like a fake or a test helper', () {
    final named = RegExp(r'fake|_fakes|testing');
    for (final file in files) {
      expect(file.split('/').last, isNot(matches(named)), reason: file);
    }
  });
}
