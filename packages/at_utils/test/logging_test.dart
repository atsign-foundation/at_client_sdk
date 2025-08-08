import 'package:at_utils/at_logger.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    AtSignLogger.defaultLoggingHandler = AtSignLogger.consoleLoggingHandler;
  });

  group('A group of AtSignLogger tests', () {
    test('Test logging handler', () {
      var records = <LogRecord>[];
      var testLogger = AtSignLogger('test_console_logging');
      testLogger.logger.onRecord.listen(records.add);
      testLogger.info('hello');
      expect(records[0].message, 'hello');
    });

    test('Test default logging handler', () {
      var lh1 = MyLoggingHandler(AtSignLogger.consoleLoggingHandler);
      AtSignLogger.defaultLoggingHandler = lh1;
      var l1 = AtSignLogger('console');

      l1.info('testing 1');
      expect(lh1.lastLogRecord!.message, 'testing 1');

      var lh2 = MyLoggingHandler(AtSignLogger.stdErrLoggingHandler);
      AtSignLogger.defaultLoggingHandler = lh2;
      var l2 = AtSignLogger('stderr');
      l2.info('testing 2');
      expect(lh2.lastLogRecord!.message, 'testing 2');
    });

    test('Test override logging handler for instance', () {
      var testDefaultLH = MyLoggingHandler(ConsoleLoggingHandler());
      AtSignLogger.defaultLoggingHandler = testDefaultLH;

      expect(AtSignLogger.defaultLoggingHandler, testDefaultLH);
      var lh1 = NullLoggingHandler();
      var l1 = AtSignLogger('null handler', loggingHandler: lh1);

      expect(AtSignLogger.defaultLoggingHandler, testDefaultLH);
      var l2 = AtSignLogger('console'); // should use the defaultLoggingHandler

      l1.info('testing per-instance logging handler');
      expect(
          lh1.lastLogRecord!.message, 'testing per-instance logging handler');
      expect(testDefaultLH.lastLogRecord, null);

      l2.info('testing with default logging handler');
      expect(
          lh1.lastLogRecord!.message, 'testing per-instance logging handler');
      expect(testDefaultLH.lastLogRecord!.message,
          'testing with default logging handler');
    });
  });
}

class MyLoggingHandler implements LoggingHandler {
  final LoggingHandler delegate;
  MyLoggingHandler(this.delegate);
  LogRecord? lastLogRecord;
  @override
  void call(LogRecord record) {
    lastLogRecord = record;
    delegate.call(record);
  }
}

class NullLoggingHandler implements LoggingHandler {
  LogRecord? lastLogRecord;
  @override
  void call(LogRecord record) {
    lastLogRecord = record;
  }
}
