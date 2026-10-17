import 'dart:async';
import 'dart:io';

import 'package:at_utils/at_logger.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Catalogue: features/logging/atsign_logger.feature
void main() {
  const String withControls = 'k\r\x1b[2J\nyy';
  const String withControlsHanded = r'k\r\x1b[2J' '\n  yy';

  late _KeepingHandler handler;
  late AtSignLogger logger;

  setUp(() {
    handler = _KeepingHandler();
    logger = AtSignLogger('records', loggingHandler: handler);
  });

  test(
      'A message\'s control characters other than LF reach the handler as'
      ' visible escapes', () {
    logger.info(withControls);
    expect(handler.records.single.message, withControlsHanded);
  });

  test('A line in a message cannot start a record', () {
    logger.info('a\nINFO|x');
    expect(handler.records.single.message, 'a\n  INFO|x');
  });

  test(
      'A message\'s bidirectional formatting characters reach the handler as'
      ' visible escapes', () {
    logger.info('a\u202eb\u2066c');
    expect(handler.records.single.message, r'a\u202eb\u2066c');
  });

  test('A line or paragraph separator in a message cannot start a line', () {
    logger.info('a\u2028INFO|x\u2029y');
    expect(handler.records.single.message, r'a\u2028INFO|x\u2029y');
  });

  test('An emoji sequence in a message reaches the handler unchanged', () {
    const String emoji = '@\u{1F469}\u200d\u{1F4BB} \u2764\ufe0f'
        ' \u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}';
    logger.info(emoji);
    expect(handler.records.single.message, emoji);
  });

  test('A backslash in a message reaches the handler unchanged', () {
    logger.info(r'C:\logs\x1b');
    expect(handler.records.single.message, r'C:\logs\x1b');
  });

  test(
      'A message with nothing to escape reaches the handler as the record'
      ' logged', () {
    final List<LogRecord> made = [];
    logger.logger.onRecord.listen(made.add);
    logger.info('hello');
    expect(handler.records.single, same(made.single));
  });

  test(
      'A stack trace logged as the message reaches the handler with each later'
      ' line indented', () {
    final StackTrace twoFrames = StackTrace.fromString(
        '#0      main (file:///a.dart:1:1)\n#1      run (file:///b.dart:2:2)\n');
    logger.warning(twoFrames);
    expect(handler.records.single.message,
        '#0      main (file:///a.dart:1:1)\n  #1      run (file:///b.dart:2:2)\n  ');
  });

  test(
      'A logger name\'s control characters reach the handler as visible'
      ' escapes', () {
    AtSignLogger('sync\nINFO', loggingHandler: handler).info('hello');
    expect(handler.records.single.loggerName, r'sync\nINFO');
  });

  test('A record\'s error and stack trace reach the handler unchanged', () {
    final StateError error = StateError('bad\nthing');
    final StackTrace stackTrace = StackTrace.current;
    logger.severe('fail\red', error, stackTrace);
    expect(handler.records.single.message, r'fail\red');
    expect(handler.records.single.error, same(error));
    expect(handler.records.single.stackTrace, same(stackTrace));
  });

  test(
      'A logger built without a LoggingHandler hands defaultLoggingHandler the'
      ' escaped message', () {
    final LoggingHandler previous = AtSignLogger.defaultLoggingHandler;
    addTearDown(() => AtSignLogger.defaultLoggingHandler = previous);
    AtSignLogger.defaultLoggingHandler = handler;
    AtSignLogger('default').info('a\nINFO|x');
    expect(handler.records.single.message, 'a\n  INFO|x');
  });

  group(
      'Given an AtSignLogger whose LoggingHandler keeps each record it is'
      ' handed', () {
    test(
        'when a record logged in another zone is copied for its escapes, then'
        ' the copy keeps the level, error, stack trace, zone and object it was'
        ' logged with', () {
      final _Shown shown = _Shown('a\rb');
      final StateError error = StateError('bad');
      final StackTrace stackTrace = StackTrace.current;
      late Zone loggedIn;
      runZoned(() {
        loggedIn = Zone.current;
        logger.severe(shown, error, stackTrace);
      });
      final LogRecord handed = handler.records.single;
      expect(handed.message, r'a\rb');
      expect(handed.level, Level.SEVERE);
      expect(handed.error, same(error));
      expect(handed.stackTrace, same(stackTrace));
      expect(loggedIn, isNot(same(Zone.current)));
      expect(handed.zone, same(loggedIn));
      expect(handed.object, same(shown));
    });

    test(
        'when a message holds characters at each edge of the escaped ranges,'
        ' then only C0, DEL and C1 reach the handler as escapes', () {
      logger.info('\t\x00\x1f \x7e\x7f\x85\x9f\xa0');
      expect(handler.records.single.message,
          r'\t\x00\x1f' ' \x7e' r'\x7f\x85\x9f' '\xa0');
    });

    test(
        'when a message holds characters at each edge of the bidirectional and'
        ' separator ranges, then only the characters in those ranges reach the'
        ' handler as escapes', () {
      logger.info('\u061b\u061c\u061d\u200d\u200e\u200f\u2010'
          '\u2027\u2028\u202a\u202d\u202e\u202f\u2065'
          '\u2066\u2067\u2068\u2069\u206a');
      expect(
          handler.records.single.message,
          '\u061b'
          r'\u061c'
          '\u061d\u200d'
          r'\u200e\u200f'
          '\u2010\u2027'
          r'\u2028\u202a\u202d\u202e'
          '\u202f\u2065'
          r'\u2066\u2067\u2068\u2069'
          '\u206a');
    });

    test(
        'when a logger name holds a bidirectional formatting character, then'
        ' the handler is handed it as a visible escape', () {
      AtSignLogger('sync\u202e', loggingHandler: handler).info('hello');
      expect(handler.records.single.loggerName, r'sync\u202e');
    });

    test(
        'when a message holds every character in the escaped ranges, then the'
        ' handler is handed none of them except LF', () {
      final Set<int> escapedRanges = {
        for (int c = 0x00; c <= 0x1f; c++) c,
        for (int c = 0x7f; c <= 0x9f; c++) c,
        0x061c,
        0x200e,
        0x200f,
        for (int c = 0x2028; c <= 0x202e; c++) c,
        for (int c = 0x2066; c <= 0x2069; c++) c,
      };
      logger.info(String.fromCharCodes(escapedRanges));
      expect(
          handler.records.single.message.codeUnits
              .where((int c) => c != 0x0a && escapedRanges.contains(c)),
          isEmpty);
    });
  });

  test('A listener on the underlying logger is handed the message as logged',
      () {
    final List<LogRecord> made = [];
    logger.logger.onRecord.listen(made.add);
    logger.info('k\ryy');
    expect(made.single.message, 'k\ryy');
  });

  group('A built-in handler writes the escaped message', () {
    void expectTwoLines(String written) {
      final List<String> lines =
          written.replaceFirst(RegExp(r'\n$'), '').split('\n');
      expect(lines, hasLength(2));
      expect(lines[0], endsWith(r'k\r\x1b[2J'));
      expect(lines[1], '  yy');
    }

    test('ConsoleLoggingHandler', () {
      final StringBuffer printed = StringBuffer();
      late AtSignLogger console;
      runZoned(
          () => console =
              AtSignLogger('console', loggingHandler: ConsoleLoggingHandler()),
          zoneSpecification: ZoneSpecification(
              print: (_, __, ___, line) => printed.writeln(line)));
      console.info(withControls);
      expectTwoLines(printed.toString());
    });

    test('StdErrLoggingHandler', () {
      final _CapturingStdout captured = _CapturingStdout();
      late AtSignLogger stdErr;
      IOOverrides.runZoned(
          () => stdErr =
              AtSignLogger('stderr', loggingHandler: StdErrLoggingHandler()),
          stderr: () => captured);
      stdErr.info(withControls);
      expectTwoLines(captured.text.toString());
    });

    test('FileLoggingHandler', () {
      final Directory dir = Directory.systemTemp.createTempSync('log_record');
      addTearDown(() => dir.deleteSync(recursive: true));
      final String path = '${dir.path}/records.log';
      AtSignLogger('file', loggingHandler: FileLoggingHandler(path))
          .info(withControls);
      expectTwoLines(File(path).readAsStringSync());
    });

    test('CLILoggingHandler', () {
      final _CapturingStdout captured = _CapturingStdout();
      late AtSignLogger cli;
      IOOverrides.runZoned(
          () => cli = AtSignLogger('cli', loggingHandler: CLILoggingHandler()),
          stderr: () => captured);
      cli.info(withControls);
      expectTwoLines(captured.text.toString());
    });
  });
}

class _KeepingHandler implements LoggingHandler {
  final List<LogRecord> records = [];

  @override
  void call(LogRecord record) => records.add(record);
}

class _Shown {
  final String text;

  _Shown(this.text);

  @override
  String toString() => text;
}

class _CapturingStdout implements Stdout {
  final StringBuffer text = StringBuffer();

  @override
  void write(Object? object) => text.write(object);

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
