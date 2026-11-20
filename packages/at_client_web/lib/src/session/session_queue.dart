import 'dart:async';

/// The key opens queue on for [atSign] (already normalised) as
/// [enrollmentId]: at_client files its clients by that pair.
String openLock(String atSign, String enrollmentId) => '$atSign $enrollmentId';

/// Runs [open] once every open started earlier under [lock] has ended,
/// however it ended, and returns its result.
///
/// Building a client checks for a live one and registers its own across
/// awaits, so two opens running together would both pass the check. Every
/// path that builds a client for an (atSign, enrollment) queues here, so
/// they wait on each other whichever way they were started.
Future<T> queuedOpen<T>(String lock, Future<T> Function() open) async {
  final previous = _opening[lock];
  final done = Completer<void>();
  _opening[lock] = done;
  try {
    if (previous != null) await previous.future;
    return await open();
  } finally {
    done.complete();
    if (identical(_opening[lock], done)) {
      _opening.remove(lock);
    }
  }
}

/// Completed when the newest open running for each lock ends; it never
/// completes with an error.
final _opening = <String, Completer<void>>{};
