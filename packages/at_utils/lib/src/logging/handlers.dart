import 'dart:io';

import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';

/// Handler class for AtSignLogger.
///
/// Implement this interface to create custom log handlers.
abstract class LoggingHandler {
  //Can extend LogRecord if any atsign specific field has to be logged
  void call(LogRecord record);
}

/// Outputs log messages to stdout in pipe-delimited format.
///
/// Format: `LEVEL|timestamp|loggerName|message`
class ConsoleLoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    print(
        '${record.level.name}|${record.time}|${record.loggerName}|${record.message} \n');
  }
}

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
    f.writeStringSync(
        '${record.level.name}|${record.time}|${record.loggerName}|${record.message} \n');
    f.closeSync();
  }
}

/// Outputs log messages to stderr in pipe-delimited format.
///
/// Format: `LEVEL|timestamp|loggerName|message`
class StdErrLoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    stderr.write(
        '${record.level.name}|${record.time}|${record.loggerName}|${record.message} \n');
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
