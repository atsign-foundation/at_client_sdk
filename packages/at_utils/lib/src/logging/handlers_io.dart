import 'dart:io';

import 'package:at_utils/src/logging/handlers.dart';
import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';

/// The `dart:io`-backed logging handlers, selected by `at_logger.dart` when
/// `dart.library.io` is available.
///
/// `handlers_stub.dart` declares the same three classes with the same
/// constructors for web/WASM builds, so nothing that names them has to change
/// per platform. Keep the two files in step — `test/logging_handlers_test.dart`
/// asserts they agree.

/// Appends log messages to a file in pipe-delimited format.
///
/// Format: `LEVEL|timestamp|loggerName|message`
///
/// ## Usage
/// ```dart
/// var logger = AtSignLogger('MyApp');
/// logger.loggingHandler = FileLoggingHandler('app.log');
/// ```
class FileLoggingHandler implements LoggingHandler {
  late File _file;

  FileLoggingHandler(String filename) {
    _file = File(filename);
  }

  @override
  void call(LogRecord record) {
    var f = _file.openSync(mode: FileMode.append);
    f.writeStringSync(logRecordLine(record));
    f.closeSync();
  }
}

/// Outputs log messages to stderr in pipe-delimited format.
///
/// Format: `LEVEL|timestamp|loggerName|message`
class StdErrLoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    stderr.write(logRecordLine(record));
  }
}

/// A logging handler that outputs colored log messages to stderr for CLIs.
///
/// Formats logs with color-coded severity levels for better terminal readability.
///
/// ## Usage
/// ```dart
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
  ///
  /// The label text itself comes from [cliLevelLabel], shared with the web stub
  /// so the two platforms cannot disagree on wording; only the colour is added
  /// here.
  String _getColoredLevel(Level level) {
    final label = cliLevelLabel(level);
    switch (level) {
      case Level.WARNING:
        return chalk.yellow(label);
      case Level.SEVERE:
      case Level.SHOUT:
        return chalk.red(label);
      case Level.INFO:
        return chalk.blueBright(label);
      case Level.FINER:
      case Level.FINEST:
      default:
        return chalk.gray(label);
    }
  }
}
