import 'package:logging/logging.dart';

/// Handler class for AtSignLogger.
///
/// Implement this interface to create custom log handlers. An AtSignLogger
/// hands its handler each record with the message and logger name escaped as
/// its constructor describes, and the error, stack trace and object unchanged.
/// A record with something to escape is a copy, with its own time and
/// sequence number.
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
        '${record.level.name}|${record.time}|${record.loggerName}|${record.message}');
  }
}
