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

/// The opens running for each lock; a caller beyond one lock's cap is refused.
///
/// An open builds and authenticates a whole client and holds it until it
/// ends, so one lock's queue is capped at 16 rather than an item lock's
/// default of 64: a stalled open would pin that much memory and a whole
/// credential's worth of work, and a caller that has sixteen opens waiting on
/// one lock is already looping. An item's queue of 64 writes is ordinary
/// traffic. A saturated open queue rejects the next open instead of growing.
final _opening = KeyedQueue<String>(maxQueuedPerKey: 16);
