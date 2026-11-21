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
  final files = _exported('at_client_web_web.dart');
  final sources = {
    for (final f in files) f: File('lib/$f').readAsStringSync(),
  };

  test('exports the passkey entry points', () {
    final barrel = File('lib/at_client_web_web.dart').readAsStringSync();
    expect(
        barrel,
        matches(RegExp(
            r"^export '[^']*web_passkey_entry\.dart'\s+show[^;]*"
            r'\bonboardNewAtSign\b[^;]*\bpasskeyLogin\b[^;]*\bprfSupported\b',
            multiLine: true)));
  });

  test('exports the call that clears a recorded PRF miss', () {
    final barrel = File('lib/at_client_web_web.dart').readAsStringSync();
    expect(
        barrel,
        matches(RegExp(
            r"^export '[^']*web_passkey_entry\.dart'\s+show[^;]*"
            r'\bclearPrfMiss\b',
            multiLine: true)));
  });

  test('exports the setup lock timeout', () {
    final barrel = File('lib/at_client_web_web.dart').readAsStringSync();
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

  test('re-exports the core API and in-memory storage completely', () {
    final barrel = File('lib/at_client_web_web.dart').readAsStringSync();
    for (final library in ['at_client.dart', 'memory.dart']) {
      expect(barrel, contains("export 'package:at_client/$library';\n"),
          reason: 'package:at_client/$library is re-exported with no show '
              'or hide');
    }
  });

  test(
      'the barrel re-exports exactly the core API, in-memory storage, and the '
      'session and exceptions of the passkey entry points, and no other '
      'exported file re-exports a package', () {
    final reExport = RegExp(r"^export 'package:[^;]*;", multiLine: true);
    final space = RegExp(r'\s+');
    for (final MapEntry(:key, :value) in sources.entries) {
      expect(
          reExport.allMatches(value).map((m) => m[0]!.replaceAll(space, ' ')),
          key == 'at_client_web_web.dart'
              ? [
                  "export 'package:at_auth/passkey.dart' show "
                      'PasskeyCeremonyException, '
                      'PasskeyRecordAuthenticationException, '
                      'PrfUnavailableException, '
                      'UnsupportedPasskeyRecordException;',
                  "export 'package:at_client/at_client.dart';",
                  "export 'package:at_client/memory.dart';",
                  "export 'package:at_client/passkey.dart' show "
                      'AtServerAtKeysLockedException, '
                      'AtServerAtKeysWriteException, '
                      'MissingAtKeysDocumentException, '
                      'PasskeyLostException, '
                      'PasskeyOnboardingIncompleteException, '
                      'PasskeySession, '
                      'PkamRefusedException, '
                      'PublicKeyMismatchException;',
                ]
              : isEmpty,
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
