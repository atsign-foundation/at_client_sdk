import 'dart:async';

/// Runs [open], a Hive box open or a call that makes one, so that its failure
/// reaches the caller once.
///
/// NOTE: hive completes the future it parks concurrent openers on with the
/// error it throws, and nothing listens to that future, so a failed open is
/// also an unhandled asynchronous error, which ends a command-line isolate.
/// [open] runs in a zone that drops that second report: once [open] has
/// failed, an uncaught error that is the caller's error, or is quoted in it,
/// as a store wrapping hive's error quotes it. Every other uncaught error goes
/// on to the zone this was called from.
Future<T> openReportingOnce<T>(Future<T> Function() open) {
  final caller = Zone.current;
  final result = Completer<T>();
  final early = <(Object, StackTrace)>[];
  Object? failure;
  var settled = false;

  bool reportsFailure(Object error) {
    final f = failure;
    if (f == null) return false;
    if (identical(error, f)) return true;
    final quoted = '$error';
    return quoted.isNotEmpty && '$f'.contains(quoted);
  }

  void pass(Object error, StackTrace stackTrace) {
    if (!reportsFailure(error)) caller.handleUncaughtError(error, stackTrace);
  }

  runZonedGuarded(() async {
    try {
      result.complete(await open());
    } catch (e, st) {
      failure = e;
      result.completeError(e, st);
    }
    settled = true;
    for (final (e, st) in early) {
      pass(e, st);
    }
  }, (e, st) => settled ? pass(e, st) : early.add((e, st)));
  return result.future;
}
