/// The terminal-only corner of at_utils: everything that depends on
/// `package:chalkdart`.
///
/// Exported from `package:at_utils/at_utils_cli.dart` and from nowhere else.
/// chalkdart names `dart:io` directly (terminal and platform probing in its
/// `chalk.dart` and `ansiutils.dart`) and ships no web-safe entry point, so
/// anything reachable from `at_logger.dart` or `at_progress.dart` that touches
/// chalk drags `dart:io` into every consumer of those barrels — at_chops,
/// at_auth, at_lookup and at_client included. Keeping chalk behind a barrel that
/// only CLIs import is what stops that.
///
/// ANSI escapes are a terminal convention: they are noise in a log file, a
/// Flutter widget and a browser console alike. So this is not only about
/// `dart:io` — it is where colour belongs regardless of platform.
// chalk's colour getters are callable objects, so returning them as `Function`
// is an implicit tear-off. That is the shape ChalkFunction has always had.
// ignore_for_file: implicit_call_tearoffs
library;

import 'dart:io';

import 'package:at_utils/src/logging/handlers.dart';
import 'package:at_utils/src/logging/progress.dart';
import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';

/// A logging handler that outputs colored log messages to stderr for CLIs.
///
/// Formats logs with color-coded severity levels for better terminal readability.
///
/// ## Usage
/// ```dart
/// import 'package:at_utils/at_utils_cli.dart';
///
/// AtSignLogger.root_level = 'INFO';
/// var logger = AtSignLogger('MyApp', loggingHandler: CLILoggingHandler());
/// logger.info('Application started');
/// ```
class CLILoggingHandler implements LoggingHandler {
  /// Handles a log record by writing it to stderr with color formatting.
  ///
  /// Output format: [LEVEL] message
  @override
  void call(LogRecord record) {
    final String coloredLevel = _getColoredLevel(record.level);
    stderr.writeln('[${chalk.bold(coloredLevel)}] ${record.message}');
  }

  /// Returns a color-coded label for the given log level.
  String _getColoredLevel(Level level) {
    switch (level) {
      case Level.WARNING:
        return chalk.yellow('WARN');
      case Level.SEVERE:
      case Level.SHOUT:
        return chalk.red('ERROR');
      case Level.INFO:
        return chalk.blueBright('INFO');
      case Level.FINER:
      case Level.FINEST:
      default:
        return chalk.gray('FINER');
    }
  }
}

/// A useful extension to assist in colour-coding output based on the
/// [ProgressEventType].
///
/// [ProgressEvent.toString()] is deliberately plain, so a CLI rendering a
/// progress stream applies this itself:
///
/// ```dart
/// stderr.writeln('${event.type.chalkFn(event.group)} : ${event.msg}');
/// ```
extension ChalkFunction on ProgressEventType {
  Function get chalkFn {
    switch (this) {
      case ProgressEventType.info:
        return chalk.blue;
      case ProgressEventType.success:
        return chalk.green;
      case ProgressEventType.warning:
        return chalk.orange;
      case ProgressEventType.error:
        return chalk.red;
    }
  }
}
