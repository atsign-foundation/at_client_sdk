import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;

/// Captures what production logs, so a claim about a log LEVEL is asserted
/// rather than eyeballed.
///
/// A level is a contract wherever the log is the only signal a caller gets:
/// an event dropped inside a loop, a namespace a sweep could not finish, a
/// step skipped for a reason the return value cannot carry. Demote one to
/// `finer` and the omission reads as success, with nothing red to say so.
///
/// **Install it before the code under test first logs.** Every at_client
/// library holds its logger in a top-level `final`, which Dart initialises
/// lazily on first use and which binds `AtSignLogger.defaultLoggingHandler` as
/// it stands *then* — so a handler installed after that call binds nothing and
/// records nothing. From `setUpAll`, before any test body runs, is the
/// reliable point. [installOn] does that and pins the level too, so a
/// `root_level` set elsewhere cannot silently empty the recorder and turn
/// every assertion reading it into a pass.
///
/// **Give any assertion over it a control that is not drawn from the property
/// under test** — a record the same call emits regardless. Without one, an
/// unbound recorder satisfies every level assertion by matching nothing, and
/// an instrument that measured nothing is indistinguishable from one that
/// measured the right thing.
///
/// The parameter is `dynamic` rather than `LogRecord`: overriding with a
/// supertype is legal, and it keeps `package:logging` — which at_client
/// depends on nowhere — out of the dependency list for the sake of a test.
class RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) => records
      .add((level: '${record.level.name}', message: '${record.message}'));

  /// The messages logged at [level], spelled as `package:logging` spells it —
  /// `SEVERE`, `WARNING`, `INFO`, `FINER`.
  Iterable<String> at(String level) =>
      records.where((r) => r.level == level).map((r) => r.message);

  /// Makes this the handler every logger built from now on binds, at [level].
  ///
  /// Call from `setUpAll`. Nothing restores the previous handler because
  /// nothing can: a logger that has already bound one keeps it for the life of
  /// the isolate, and `dart test` gives each test file its own.
  void installOn({String level = 'info'}) {
    AtSignLogger.defaultLoggingHandler = this;
    AtSignLogger.root_level = level;
  }
}
