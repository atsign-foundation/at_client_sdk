import 'package:at_utils/src/logging/handlers.dart';
import 'package:logging/logging.dart';

/// Web/WASM stand-ins for the `dart:io`-backed handlers in `handlers_io.dart`,
/// selected by `at_logger.dart` when `dart.library.io` is unavailable.
///
/// A browser has no file system and no stderr, so all three route to the console
/// instead — the same destination [ConsoleLoggingHandler] uses, in the same
/// [logRecordLine] format. Each warns once, on first use, so a developer
/// wondering why `app.log` is empty gets told rather than left guessing.
///
/// Redirecting rather than throwing is deliberate: a logging call should never
/// be the thing that takes down an application. It does mean a web build
/// silently gets console output where a native build writes a file, which is
/// the trade-off the warning exists to surface.
///
/// These declare the same class names and constructors as `handlers_io.dart`, so
/// code naming them compiles on both platforms.

final Set<String> _warned = {};

void _warnOnce(String handler, String unavailable) {
  if (_warned.add(handler)) {
    print('WARNING|at_utils|$handler: $unavailable is not available on this '
        'platform — logging to the console instead.');
  }
}

/// Console-backed stand-in for the `dart:io` `FileLoggingHandler`.
///
/// Accepts and ignores [filename]; there is no file system to write to.
class FileLoggingHandler implements LoggingHandler {
  final String filename;

  FileLoggingHandler(this.filename);

  @override
  void call(LogRecord record) {
    _warnOnce('FileLoggingHandler', 'writing to "$filename"');
    print(logRecordLine(record));
  }
}

/// Console-backed stand-in for the `dart:io` `StdErrLoggingHandler`.
class StdErrLoggingHandler implements LoggingHandler {
  @override
  void call(LogRecord record) {
    _warnOnce('StdErrLoggingHandler', 'stderr');
    print(logRecordLine(record));
  }
}
