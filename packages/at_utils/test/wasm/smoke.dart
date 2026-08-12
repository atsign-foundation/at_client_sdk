// The entry point for the `dart compile wasm` step of the `wasm_compile` job in
// .github/workflows/at_libraries.yaml. It is compiled, never run by CI — the
// only thing that matters is that compiling it reaches all of at_utils' web-safe
// barrels.
//
// What this catches that dep_tree_test.dart cannot: `dart:ffi`, the one library
// dart2wasm rejects outright. `dart:io` it will NOT catch — dart2wasm accepts
// that and throws at runtime instead, which is the shakedown's job.
//
// Everything here is deliberately *used*, so no part of the barrels can be
// tree-shaken away before the compiler resolves its imports. That includes the
// back-compat re-exports (`StdErrLoggingHandler`, `FileLoggingHandler`,
// `chalkFn`) which must resolve to their uncoloured console stubs rather than
// dragging chalkdart in.
//
// Run it by hand with:
//   dart compile wasm test/wasm/smoke.dart -o /tmp/smoke.wasm
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';
import 'package:logging/logging.dart' show Level, LogRecord;

void main() {
  AtSignLogger.root_level = 'info';
  final logger = AtSignLogger('smoke');
  logger.info('console handler');

  // The handlers reached through the dart.library.io conditional export, plus
  // the statics on AtSignLogger that name their types.
  AtSignLogger.defaultLoggingHandler = AtSignLogger.stdErrLoggingHandler;
  AtSignLogger('smoke.stderr', loggingHandler: StdErrLoggingHandler())
      .warning('stderr handler');
  AtSignLogger('smoke.file', loggingHandler: FileLoggingHandler('smoke.log'))
      .severe('file handler');
  AtSignLogger.defaultLoggingHandler = AtSignLogger.consoleLoggingHandler;

  final event =
      ProgressEvent(group: 'smoke', msg: 'm', type: ProgressEventType.success);
  final record =
      LogRecord(Level.INFO, 'formatted', 'smoke.fmt', null, null, null, null);

  print([
    logger.level,
    ConsoleLoggingHandler().runtimeType,
    logRecordLine(record).trim(),
    // The back-compat ChalkFunction re-export: the uncoloured stub on web.
    event.type.chalkFn('colour'),
    event.toString().contains('smoke'),
    ProgressEventType.values.length,
    const ProgressPublisherShape().runtimeType,
  ].join(','));
}

/// Names [ProgressPublisher] so the interface cannot be tree-shaken out of the
/// barrel before the compiler resolves it.
class ProgressPublisherShape implements ProgressPublisher {
  const ProgressPublisherShape();

  @override
  Stream<ProgressEvent> subscribeProgress() => const Stream.empty();
}
