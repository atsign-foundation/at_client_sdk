import 'dart:io';

import 'package:at_utils/src/logging/handlers.dart';
import 'package:logging/logging.dart';

/// The `dart:io`-backed logging handlers, selected by `at_logger.dart` when
/// `dart.library.io` is available.
///
/// `handlers_stub.dart` declares the same two classes with the same
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
