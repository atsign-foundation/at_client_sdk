import 'package:logging/logging.dart';

/// The platform-neutral half of at_utils' logging handlers: the
/// [LoggingHandler] interface and [ConsoleLoggingHandler], the default.
///
/// The handlers that need `dart:io` — `FileLoggingHandler` and
/// `StdErrLoggingHandler` — live in `handlers_io.dart`,
/// with console-backed equivalents in `handlers_stub.dart`. `at_logger.dart`
/// picks between those two with an `if (dart.library.io)` conditional export, so
/// all three names remain importable from `package:at_utils/at_logger.dart` on
/// every platform. Keeping them out of *this* file is what lets `at_logger.dart`
/// — which `at_chops`, `at_auth`, `at_lookup` and `at_client` all import — stay
/// free of `dart:io`.
///
/// [logRecordLine] is the shared wire format, so every handler on every
/// platform emits byte-identical output.

/// Handler class for AtSignLogger.
///
/// Implement this interface to create custom log handlers.
abstract class LoggingHandler {
  //Can extend LogRecord if any atsign specific field has to be logged
  void call(LogRecord record);
}

/// The pipe-delimited line every built-in handler emits:
/// `LEVEL|timestamp|loggerName|message`.
///
/// Shared so the `dart:io` handlers and their web stubs cannot drift apart. The
/// trailing space-newline is preserved from the original implementation.
String logRecordLine(LogRecord record) =>
    '${record.level.name}|${record.time}|${record.loggerName}|${record.message} \n';

/// Outputs log messages to stdout in pipe-delimited format.
///
/// Format: `LEVEL|timestamp|loggerName|message`
class ConsoleLoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    print(logRecordLine(record));
  }
}
