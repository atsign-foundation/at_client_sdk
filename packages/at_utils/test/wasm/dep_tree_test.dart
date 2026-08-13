// These gates read the filesystem to inspect sources, so they run on the VM
// only. Without this they would be compiled and launched by the T2
// node+dart2wasm platform run, where dart:io throws and the failure looks like a
// neutrality problem rather than a test that was never meant to run there.
@TestOn('vm')
library;

import 'package:test/test.dart'; // for the @TestOn annotation above
import 'package:wasm_shakedown/ratchet.dart';

/// Dependency-tree ratchet for at_utils' barrels.
///
/// at_utils sits beneath at_chops, at_auth, at_lookup and at_client, so a
/// `dart:io` leak here reaches every one of them. That also means at_utils'
/// three offenders are the reason `at_utils` appears in four other packages'
/// blocked sets — fixing them is the single highest-leverage item in the sweep.
///
/// Why a graph walk rather than a compile: `dart compile wasm` **accepts**
/// `dart:io`. It ships a stub that throws on first use, so a browser-hostile
/// import compiles clean and fails in the browser instead. Nothing the compiler
/// does can police this; measured on Dart 3.12.
///
/// Baselines taken 2026-08-13 against trunk `20f7f4da5`. Regenerate with
/// `dart run wasm_shakedown:baseline <barrel>`.
void main() {
  // The full barrel. `app_config.dart` and `pseudo_server_socket.dart` are what
  // make it native-only; `PseudoServerSocket` is used by at_server for ALPN
  // multiplexing, so the barrel gets split rather than the file deleted.
  ratchetGroup(
    'package:at_utils/at_utils.dart',
    package: 'at_utils',
    expectedOffenders: const <String, List<String>>{
      'lib/src/config/app_config.dart': ['dart:io'],
      'lib/src/logging/handlers.dart': ['dart:io'],
      'lib/src/networking/pseudo_server_socket.dart': ['dart:io'],
    },
    expectedBlocked: const <String>{'at_utils', 'chalkdart'},
    minFilesWalked: 150,
  );

  // The logger. `handlers.dart` carries FileLoggingHandler, StdErrLoggingHandler
  // and CLILoggingHandler behind a single `dart:io` import at the top, which
  // poisons the whole logger for a web build — ConsoleLoggingHandler is pure
  // `print` and would otherwise be neutral.
  ratchetGroup(
    'package:at_utils/at_logger.dart',
    package: 'at_utils',
    expectedOffenders: const <String, List<String>>{
      'lib/src/logging/handlers.dart': ['dart:io'],
    },
    expectedBlocked: const <String>{'at_utils', 'chalkdart'},
    minFilesWalked: 30,
  );

  // Progress reporting owns no offending source of its own; it is blocked purely
  // by reaching chalkdart, which reads the terminal for ANSI support and has no
  // web-safe entry point. Note what that means for the ratchet: an empty
  // `expectedOffenders` is NOT the same as a neutral barrel, which is exactly
  // why the blocked-package set is asserted separately.
  ratchetGroup(
    'package:at_utils/at_progress.dart',
    package: 'at_utils',
    expectedOffenders: const <String, List<String>>{},
    expectedBlocked: const <String>{'chalkdart'},
    minFilesWalked: 8,
  );
}
