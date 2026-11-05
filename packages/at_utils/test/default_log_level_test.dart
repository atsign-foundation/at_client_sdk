import 'package:at_utils/at_logger.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// A program that sets no log level hears what the SDK warns about and nothing
/// below it.
void main() {
  group('Given a program that sets no log level', () {
    test(
        'when the SDK logs at info and at warning, then only the warning '
        'reaches the handler', () {
      final handled = _Recording();
      final logger = AtSignLogger('sdk', loggingHandler: handled);

      logger.info('an info line');
      logger.warning('a warning line');

      expect(handled.messages, ['a warning line']);
      expect(AtSignLogger.root_level, 'warning');
    });
  });
}

class _Recording implements LoggingHandler {
  final List<String> messages = [];

  @override
  void call(LogRecord record) => messages.add(record.message);
}
