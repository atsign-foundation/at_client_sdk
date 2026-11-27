import '../keyed_queue.dart';

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
Future<T> queuedOpen<T>(String lock, Future<T> Function() open) =>
    _opening.run(lock, open);

/// The opens running for each lock; it never completes with an error.
final _opening = KeyedQueue<String>();
