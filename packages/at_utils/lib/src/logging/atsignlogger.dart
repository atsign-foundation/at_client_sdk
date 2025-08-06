// ignore_for_file: non_constant_identifier_names

import 'package:at_utils/src/logging/handlers.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:logging/logging.dart' as logging;

/// Class for AtSignLogger Implementation
class AtSignLogger {
  late logging.Logger logger;
  String? _level;
  static String _root_level = 'info';
  bool _hierarchicalLoggingEnabled = false;

  static final ConsoleLoggingHandler consoleLoggingHandler =
      ConsoleLoggingHandler();
  static final StdErrLoggingHandler stdErrLoggingHandler =
      StdErrLoggingHandler();

  /// The default logging handler to log events.
  ///
  /// Defaults to [ConsoleLoggingHandler] which writes log events to console.
  static LoggingHandler defaultLoggingHandler = consoleLoggingHandler;

  /// The AtSignLogger is a wrapper on the Logger to log events.
  ///
  /// * name: Accepts String as input which represents the name of the AtSignLogger instance.
  ///
  /// * loggingHandler  This is an optional parameter that determines the destination for logging events.
  ///
  /// The loggingHandler defaults to the value of [defaultLoggingHandler].
  ///
  /// To customize the logging behavior based on your specific requirements, create an
  /// instance of a class that implements the [LoggingHandler] interface and pass this
  /// instance to the loggingHandler argument
  ///
  /// ```dart
  /// class MyLoggingHandler implements LoggingHandler {
  ///   @override
  ///   void call(LogRecord record) {
  ///     // Custom implementation of logging behavior
  ///     print('Logging: ${record.message}');
  ///   }
  /// }
  ///
  /// AtSignLogger('myLogger', loggingHandler: MyLoggingHandler())
  /// ```
  AtSignLogger(String name, {LoggingHandler? loggingHandler}) {
    logger = logging.Logger.detached(name);
    loggingHandler ??= defaultLoggingHandler;
    logger.onRecord.listen(loggingHandler);
    level = _root_level;
  }

  String? get level {
    return LogLevel.level.keys
        .firstWhereOrNull((k) => LogLevel.level[k].toString() == _level);
  }

  set level(String? value) {
    if (!_hierarchicalLoggingEnabled) {
      _hierarchicalLoggingEnabled = true;
      logging.hierarchicalLoggingEnabled = _hierarchicalLoggingEnabled;
    }
    _level = value;
    logger.level = LogLevel.level[_level!];
  }

  bool isLoggable(String value) => (LogLevel.level[value]! >= logger.level);

  // ignore: unnecessary_getters_setters
  bool get hierarchicalLoggingEnabled {
    return _hierarchicalLoggingEnabled;
  }

  set hierarchicalLoggingEnabled(bool value) {
    _hierarchicalLoggingEnabled = value;
  }

  static set root_level(String rootLevel) {
    _root_level = rootLevel.toLowerCase();
    logging.Logger.root.level = LogLevel.level[_root_level] ??
        logging.Level.INFO; // defaults to Level.INFO
  }

  static String get root_level {
    return _root_level;
  }

  //log methods
  void shout(message, [Object? error, StackTrace? stackTrace]) =>
      logger.shout(message, error, stackTrace);

  void severe(message, [Object? error, StackTrace? stackTrace]) =>
      logger.severe(message, error, stackTrace);

  void warning(message, [Object? error, StackTrace? stackTrace]) =>
      logger.warning(message, error, stackTrace);

  void info(message, [Object? error, StackTrace? stackTrace]) =>
      logger.info(message, error, stackTrace);

  void finer(message, [Object? error, StackTrace? stackTrace]) =>
      logger.finer(message, error, stackTrace);

  void finest(message, [Object? error, StackTrace? stackTrace]) =>
      logger.finest(message, error, stackTrace);
}

class LogLevel {
  static final Map<String, logging.Level> level = {
    'info': logging.Level.INFO,
    'shout': logging.Level.SHOUT,
    'severe': logging.Level.SEVERE,
    'warning': logging.Level.WARNING,
    'finer': logging.Level.FINER,
    'finest': logging.Level.FINEST,
    'all': logging.Level.ALL
  };
}
