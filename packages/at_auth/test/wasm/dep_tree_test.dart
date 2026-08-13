// These gates read the filesystem to inspect sources, so they run on the VM
// only. Without this they would be compiled and launched by the T2
// node+dart2wasm platform run, where dart:io throws and the failure looks like a
// neutrality problem rather than a test that was never meant to run there.
@TestOn('vm')
library;

import 'package:test/test.dart'; // for the @TestOn annotation above
import 'package:wasm_shakedown/ratchet.dart';

/// Dependency-tree ratchet for `package:at_auth/at_auth.dart`.
///
/// **Baseline only — this project does not fix these.** at_auth is owned by the
/// post-quantum program, whose S-5 moves `FileAtKeysIo` into an `at_auth_io.dart`
/// barrel, drops the `atKeysIo ??=` default and puts the registrar on
/// `package:http`. The gate is here anyway for one reason: without it, at_auth
/// can grow a new platform import between now and then and nothing would say so.
///
/// So when this fails, the question is which direction it failed in. A shrinking
/// baseline means S-5 is landing and this file should be updated to match. A
/// growing one is a regression to raise with whoever owns the change — not
/// something to baseline away.
///
/// Baseline taken 2026-08-13 against trunk `20f7f4da5`. Regenerate with
/// `dart run wasm_shakedown:baseline package:at_auth/at_auth.dart`.
void main() {
  ratchetGroup(
    'package:at_auth/at_auth.dart',
    package: 'at_auth',
    expectedOffenders: const <String, List<String>>{
      // Holds the socket probe S-5 relocates.
      'lib/src/at_auth_impl.dart': ['dart:io'],
      // The `.atKeys` file keystore — the canonical case for a platform
      // implementer package. A browser has no such file.
      'lib/src/keys/io/file_io.dart': ['dart:io'],
      // Moves to package:http under S-5.
      'lib/src/registrar/registrar_service.dart': ['dart:io'],
    },
    expectedBlocked: const <String>{
      'at_auth',
      'at_lookup',
      'at_server_status',
      'at_utils',
      'chalkdart',
      'http',
    },
    minFilesWalked: 900,
  );
}
