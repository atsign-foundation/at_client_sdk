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
