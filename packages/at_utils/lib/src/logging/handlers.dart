import 'dart:io';
import 'package:logging/logging.dart';

/// Handler class for AtSignLogger
abstract class LoggingHandler {
  //Can extend LogRecord if any atsign specific field has to be logged
  void call(LogRecord record);
}

class ConsoleLoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    print(
        '${record.level.name}|${record.time}|${record.loggerName}|${record.message} \n');
  }
}

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

class StdErrLoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    stderr.write(
        '${record.level.name}|${record.time}|${record.loggerName}|${record.message} \n');
  }
}
