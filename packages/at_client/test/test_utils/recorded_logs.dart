import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;

/// Captures what production logs, so a claim about a log level is asserted
/// rather than eyeballed.
///
/// Install it from `setUpAll`, before the code under test first logs: every
/// at_client library holds its logger in a top-level `final` that binds
/// `AtSignLogger.defaultLoggingHandler` as it stands when the logger is first
/// used, so a handler installed after that records nothing — and an unbound
/// recorder satisfies every level assertion by matching nothing.
class RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  /// [record] is `dynamic` rather than the handler interface's `LogRecord` so
  /// this file need not import `package:logging`.
  @override
  void call(dynamic record) => records
      .add((level: '${record.level.name}', message: '${record.message}'));

  /// The messages logged at [level], spelled as `package:logging` spells it —
  /// `SEVERE`, `WARNING`, `INFO`, `FINER`.
  Iterable<String> at(String level) =>
      records.where((r) => r.level == level).map((r) => r.message);

  /// Makes this the handler every logger built from now on binds, at [level].
  ///
  /// Nothing restores the previous handler because nothing can: a logger that
  /// has already bound one keeps it for the life of the isolate, and
  /// `dart test` gives each test file its own.
  void installOn({String level = 'info'}) {
    AtSignLogger.defaultLoggingHandler = this;
    AtSignLogger.root_level = level;
  }
}
