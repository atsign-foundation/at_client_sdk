import 'package:test/test.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

/// Dependency-tree shakedown for `package:at_auth/at_auth_web.dart`.
///
/// The walk itself lives in `tools/wasm_shakedown`; this file is only at_auth's
/// entry points and expectations. See that package for why an import-graph walk
/// rather than a compile: `dart compile wasm` accepts `dart:io` and defers the
/// failure to runtime, so the compiler cannot police this split.
/// `test/wasm/smoke.dart` plus `dart compile wasm` covers the complementary
/// case, `dart:ffi`, which the compiler *does* reject.
void main() {
  group('at_auth_web.dart dependency tree', () {
    late Shakedown result;

    setUpAll(() => result = shakedown('package:at_auth/at_auth_web.dart'));

    test('no at_auth-owned file names a browser-hostile library', () {
      final owned = result.offendersIn('at_auth');
      expect(
        owned,
        isEmpty,
        reason: 'These at_auth sources are reachable from at_auth_web.dart but '
            'name a platform library WASM cannot provide. Either move them '
            'behind at_auth.dart (the dart:io barrel), or — the usual cause — '
            'stop importing the public `package:at_auth/at_auth.dart` barrel '
            'from inside lib/src/ and import the narrow src path instead:\n'
            '${owned.entries.map((e) => '  ${e.key} -> ${e.value.join(', ')}').join('\n')}',
      );
    });

    test('the set of externally-blocked packages has not grown', () {
      // Measured 2026-08-12. A ratchet in BOTH directions: a new entry means
      // someone introduced a dependency that cannot run in a browser, and a
      // missing entry means a blocker was fixed and this should shrink. Either
      // way, read the failure and update it deliberately.
      const expected = {
        // at_lookup's socket transport — the T-series in
        // docs/projects/wasm/plan.md. The largest remaining blocker.
        'at_lookup',
        // at_utils: src/config/app_config.dart (File) and
        // src/networking/pseudo_server_socket.dart (ServerSocket), both
        // reachable only through the full at_utils.dart barrel — which at_auth
        // pulls in src/keys/io/at_keys_io.dart for AtSignLogger alone. Tasks
        // I1/I3; splitting that barrel needs at_server coordination.
        //
        // chalkdart dropped off this list in at_utils 3.5.0: it reaches dart:io
        // with no web-safe entry point, and was pulled in by progress.dart until
        // the CLI barrel moved colour out of the core barrels.
        'at_utils',
      };

      expect(result.blockedPackages, expected,
          reason: 'Externally-blocked packages changed.\n'
              'Offending files:\n${result.report()}');
    });

    test('the walk actually traversed the tree', () {
      expect(result.filesWalked, greaterThan(100));
      expect(result.missingFiles, isEmpty,
          reason: 'imported but not found: ${result.missingFiles}');
    });
  });

  test('at_auth.dart, the default barrel, does reach dart:io', () {
    // The other half of the invariant: if this ever comes up empty the split has
    // collapsed into one barrel and the test above became vacuous.
    final full =
        shakedown('package:at_auth/at_auth.dart').offendersIn('at_auth');
    expect(full.keys, contains('lib/src/keys/io/file_io.dart'));
    expect(full.keys, contains('lib/src/io/probe.dart'));
  });
}
