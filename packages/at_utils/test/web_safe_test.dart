import 'dart:io';

import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils_io.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_utils/web_safe.feature
void main() {
  test('The default barrels reach no platform library', () {
    for (final barrel in [
      'at_utils.dart',
      'at_logger.dart',
      'at_progress.dart'
    ]) {
      final reached = _reach('lib/$barrel');
      expect(reached.where(_isPlatformOnly), isEmpty,
          reason: '$barrel reaches no dart:io, directly or through chalkdart');
    }
    // NOTE: the control walks the io barrel the same way, so a walker that
    // reached nothing cannot pass the assertions above.
    expect(_reach('lib/at_utils_io.dart'), contains('dart:io'),
        reason: 'the io barrel holds what the default barrels leave out');
  });

  test('Native logging comes from the io barrel', () {
    final dir = Directory.systemTemp.createTempSync('at_utils_web_safe');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = '${dir.path}/log.txt';
    final record = LogRecord(Level.INFO, 'started', 'MyApp');

    FileLoggingHandler(file)(record);

    expect(
        File(file).readAsStringSync(), 'INFO|${record.time}|MyApp|started\n');
    expect(StdErrLoggingHandler(), isA<LoggingHandler>());
    expect(CLILoggingHandler(), isA<LoggingHandler>());
  });

  test('A progress event prints without terminal colour codes', () {
    final event = ProgressEvent(
        group: 'activate', msg: 'keys stored', type: ProgressEventType.warning);

    final printed = event.toString();

    expect(printed, isNot(contains('\x1b')));
    expect(printed,
        '${event.time.toIso8601String()} | ProgressEventType.warning | activate | keys stored');
  });
}

/// Every library [entry] reaches through `import` and `export`, its own files
/// followed and other packages recorded but not entered, taking each
/// conditional import's default branch, which is the web's.
Set<String> _reach(String entry) {
  final reached = <String>{};
  final pending = [entry];
  final seen = <String>{};
  final directive = RegExp(
      r'''(?:import|export)\s+'([^']+)'((?:\s+if\s*\(\s*dart\.library\.io\s*\)\s*'[^']+')?)''');
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    final source = File(path).readAsStringSync();
    for (final m in directive.allMatches(source)) {
      final uri = m.group(1)!;
      if (uri.startsWith('package:at_utils/')) {
        pending.add('lib/${uri.substring('package:at_utils/'.length)}');
      } else if (!uri.contains(':')) {
        pending.add(File(path).parent.uri.resolve(uri).toFilePath());
      } else {
        reached.add(uri);
      }
    }
  }
  return reached;
}

bool _isPlatformOnly(String uri) =>
    uri == 'dart:io' || uri.startsWith('package:chalkdart/');
