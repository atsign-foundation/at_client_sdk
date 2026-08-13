// These gates read the filesystem to inspect sources, so they run on the VM
// only. Without this they would be compiled and launched by the T2
// node+dart2wasm platform run, where dart:io throws and the failure looks like a
// neutrality problem rather than a test that was never meant to run there.
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:wasm_shakedown/ratchet.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

/// Dependency-tree ratchet for at_chops' barrels.
///
/// at_chops is the one neutral package that is **already clean**: every OpenSSL
/// and FFI algorithm lives behind `at_chops_ffi.dart`, and `at_chops.dart`
/// exports only the pure-Dart implementations. So this file's job is different
/// from the other four — it holds a line rather than baselining a backlog.
///
/// Baselines taken 2026-08-13 against trunk `20f7f4da5`. Regenerate with
/// `dart run wasm_shakedown:baseline <barrel>`.
void main() {
  // Zero at_chops-owned offenders, and that is the assertion — not a baseline to
  // shrink. `at_utils` and `chalkdart` are inherited from at_utils' logger and
  // come off this list when I1–I4 land.
  //
  // Worth reading twice: `cryptography` is NOT in this set. Under web resolution
  // its configurable imports select the pure-Dart implementation rather than the
  // `dart:html` Web Crypto path, which is what open question C1 asked. It DOES
  // appear under io resolution (see the inverse test below), so the two walks
  // together are the evidence. This is structural only — that the pure-Dart path
  // is reachable, not that it computes the right answers under WasmGC. The T2
  // node run is what establishes the second half.
  ratchetGroup(
    'package:at_chops/at_chops.dart',
    package: 'at_chops',
    expectedOffenders: const <String, List<String>>{},
    expectedBlocked: const <String>{'at_utils', 'chalkdart'},
    minFilesWalked: 500,
  );

  group('the FFI quarantine is real', () {
    // The inverse half. Without it, the assertion above goes vacuously green the
    // day someone flattens the two barrels into one — an empty offender set
    // reads identically whether the FFI island is quarantined or gone.
    //
    // Walked with io semantics because that is the only platform on which the
    // FFI barrel is meant to resolve to anything.
    late Shakedown ffi;

    setUpAll(() => ffi = shakedown('package:at_chops/at_chops_ffi.dart',
        environment: ioEnvironment));

    test('at_chops_ffi.dart still carries every FFI algorithm', () {
      expect(
          ffi.offendersIn('at_chops'),
          {
            'lib/src/algorithm/at_pqc.dart': ['dart:ffi'],
            'lib/src/algorithm/encryption/aes_gcm_ffi_algo.dart': ['dart:ffi'],
            'lib/src/algorithm/encryption/ml_kem_768_ffi.dart': ['dart:ffi'],
            'lib/src/algorithm/encryption/x25519_ffi_algo.dart': ['dart:ffi'],
            'lib/src/algorithm/encryption/x_wing_ffi.dart': ['dart:ffi'],
            'lib/src/algorithm/ffi/openssl_ffi_bindings.dart': ['dart:ffi'],
            'lib/src/algorithm/ffi/openssl_loader.dart': [
              'dart:ffi',
              'dart:io'
            ],
            'lib/src/algorithm/signing/ml_dsa_65_ffi.dart': ['dart:ffi'],
          },
          reason:
              'The FFI barrel no longer reaches the algorithms it exists to '
              'quarantine. Either they moved — in which case at_chops.dart is '
              'about to stop being neutral — or the two barrels were merged and '
              'the neutrality assertion above now proves nothing:\n'
              '${ffi.report()}');
    });

    test('the split is what keeps dart:ffi out of the web barrel', () {
      // dart2wasm *does* reject dart:ffi outright — it is the one platform
      // library the compiler catches. So this pairing is the whole reason a web
      // build of at_chops is possible at all.
      final web = shakedown('package:at_chops/at_chops.dart');
      expect(web.offenders.values.expand((libs) => libs),
          isNot(contains('dart:ffi')),
          reason: 'dart:ffi is reachable from at_chops.dart — the web build '
              'will fail to compile:\n${web.report()}');
    });
  });
}
