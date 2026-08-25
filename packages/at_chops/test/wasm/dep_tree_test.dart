// This suite reads the filesystem to inspect sources, so it runs on the VM only.
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:wasm_shakedown/ratchet.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

/// Dependency-tree ratchet for at_chops' barrels.
///
/// at_chops is the only package gated so far, because it is the only one already
/// web-safe: every OpenSSL and FFI algorithm lives behind `at_chops_ffi.dart`, and
/// `at_chops.dart` exports only the pure-Dart implementations. So this file holds a
/// line rather than recording a backlog, which is what makes it worth gating first.
/// at_utils, at_lookup, at_client and at_auth each get the same pair of files as
/// they are ported.
///
/// `cryptography` is deliberately absent from the blocked count. Under web
/// resolution its configurable imports select the pure-Dart implementation rather
/// than the `dart:html` Web Crypto path — a structural fact only, not evidence
/// that it computes the right answers under WasmGC.
void main() {
  ratchetGroup(
    'package:at_chops/at_chops.dart',
    package: 'at_chops',
    allowedOffenders: const {},
    maxBlockedPackages: 2,
    minFilesWalked: 500,
  );

  test('at_chops_ffi.dart still carries the FFI island', () {
    // The inverse half, and the only part of the quarantine a compile cannot
    // express: `compile_probe.dart` proves dart:ffi is absent from the web barrel,
    // but an empty offender set reads identically whether the FFI algorithms are
    // quarantined or simply gone. Walked with io semantics because that is the
    // only platform the FFI barrel resolves on.
    final ffi = shakedown('package:at_chops/at_chops_ffi.dart',
        environment: ioEnvironment);
    expect(ffi.offendersIn('at_chops').values.expand((libs) => libs),
        contains('dart:ffi'),
        reason: 'The FFI barrel no longer reaches the algorithms it exists to '
            'quarantine — either they moved, or the two barrels were merged and '
            'the assertion above now proves nothing:\n${ffi.report()}');
  });
}
