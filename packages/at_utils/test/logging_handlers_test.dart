import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils_cli.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Guards the conditional-export split in `at_logger.dart`, and the CLI barrel
/// that keeps chalkdart out of it.
///
/// `handlers_io.dart` and `handlers_stub.dart` declare the same two classes,
/// chosen by `if (dart.library.io)`. Nothing in the language keeps them in step,
/// so these tests pin the contract that matters to callers: the names resolve,
/// they satisfy [LoggingHandler], the constructors take the same arguments, and
/// the shared format helpers agree.
///
/// This suite runs on the VM, so it exercises the `dart:io` branch. The stub
/// branch is covered by the shared helpers below plus at_utils analysing clean
/// for web — a browser run would be the only way to exercise it directly.
void main() {
  LogRecord recordAt(Level level) =>
      LogRecord(level, 'hello', 'test.logger', null, null, null, null);

  group('handler surface is identical across the platform split', () {
    test('every handler name resolves from at_logger.dart', () {
      // Deliberately naming the concrete types: a barrel that stopped exporting
      // any of them would fail to compile here rather than silently at a
      // consumer.
      expect(ConsoleLoggingHandler(), isA<LoggingHandler>());
      expect(StdErrLoggingHandler(), isA<LoggingHandler>());
      expect(FileLoggingHandler('unused.log'), isA<LoggingHandler>());
      // From the CLI barrel, not the platform-split pair.
      expect(CLILoggingHandler(), isA<LoggingHandler>());
    });

    test('AtSignLogger exposes its handler statics', () {
      expect(AtSignLogger.consoleLoggingHandler, isA<LoggingHandler>());
      expect(AtSignLogger.stdErrLoggingHandler, isA<LoggingHandler>());
      // The documented default. Every known caller in at_client_sdk and
      // at_server assigns stdErrLoggingHandler over this, so it must stay
      // assignable from the type the statics carry.
      expect(AtSignLogger.defaultLoggingHandler,
          same(AtSignLogger.consoleLoggingHandler));
      AtSignLogger.defaultLoggingHandler = AtSignLogger.stdErrLoggingHandler;
      expect(AtSignLogger.defaultLoggingHandler,
          same(AtSignLogger.stdErrLoggingHandler));
      AtSignLogger.defaultLoggingHandler = AtSignLogger.consoleLoggingHandler;
    });
  });

  group('shared format helpers', () {
    test('logRecordLine is the pipe-delimited wire format', () {
      final line = logRecordLine(recordAt(Level.INFO));
      expect(line, startsWith('INFO|'));
      expect(line, contains('|test.logger|hello'));
      // The trailing " \n" is load-bearing: it is the format shipped before the
      // split, and both platforms must keep emitting it byte-for-byte.
      expect(line, endsWith(' \n'));
    });

    test('every ProgressEventType has a colour function', () {
      // chalkFn now lives in at_utils_cli.dart. It stays exercised here so a
      // barrel move cannot silently drop it.
      for (final type in ProgressEventType.values) {
        expect(type.chalkFn, isA<Function>(), reason: '$type has no chalkFn');
      }
    });

    test('ProgressEvent.toString() is plain text', () {
      // A model must not embed ANSI escapes: they are literal noise in a log
      // file, a Flutter widget and a browser console. Colour is the CLI's job.
      final rendered =
          ProgressEvent(group: 'g', msg: 'm', type: ProgressEventType.error)
              .toString();
      expect(rendered.codeUnits, isNot(contains(27)),
          reason: 'ESC found in: $rendered');
      expect(rendered, contains('| g'));
      expect(rendered, contains('| m'));
    });
  });
}
