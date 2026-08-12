/// Web/WASM stand-ins for the chalk-backed CLI surface in `cli.dart`.
///
/// `at_utils_cli.dart` is the canonical home for these symbols and always
/// resolves to the real `cli.dart`. This file exists purely so `at_logger.dart`
/// and `at_progress.dart` can keep exporting `CLILoggingHandler` and
/// `ChalkFunction` — as they did before at_utils 3.5.0 — without dragging
/// chalkdart, and therefore `dart:io`, into every consumer of those barrels.
///
/// **These back-compat re-exports are temporary.** They should be deleted, and
/// the symbols left only in `at_utils_cli.dart`, in the next at_utils major.
/// That major is currently blocked: `at_persistence_secondary_server` pins
/// `at_utils: ^3.0.19` in every published version, so nothing in this workspace
/// resolves against an at_utils 4.x until at_server relaxes it.
library;

import 'package:at_utils/src/logging/handlers.dart';
import 'package:at_utils/src/logging/progress.dart';
import 'package:logging/logging.dart';

bool _warned = false;

/// Console-backed stand-in for the `dart:io` `CLILoggingHandler`.
///
/// A browser has no stderr and renders ANSI escapes as literal `[34m` noise, so
/// this prints the same `[LEVEL] message` shape uncoloured. Warns once, since a
/// developer who explicitly chose the *CLI* handler in a web build has probably
/// reached for the wrong one.
class CLILoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    if (!_warned) {
      _warned = true;
      print('WARNING|at_utils|CLILoggingHandler: stderr and ANSI colour are '
          'not available on this platform — logging to the console instead.');
    }
    print('[${record.level.name}] ${record.message}');
  }
}

String _plain(String text) => text;

/// Uncoloured stand-in for the chalk-backed `ChalkFunction` in `cli.dart`.
///
/// Returns the text unchanged: ANSI escapes are terminal syntax, and emitting
/// them into a browser console would produce noise rather than colour.
extension ChalkFunction on ProgressEventType {
  Function get chalkFn => _plain;
}
