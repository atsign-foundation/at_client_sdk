import 'package:at_client/at_client.dart';

import '../exceptions.dart';
import '../keyed_queue.dart';

/// The key opens queue on for [atSign] (already normalised) as
/// [enrollmentId]: at_client files its clients by that pair.
String openLock(String atSign, String enrollmentId) => '$atSign $enrollmentId';

/// The key the keys open for [normalizedAtSign] on [keys] queues on: the
/// enrollment those keys authenticate as.
String keysOpenLock(String normalizedAtSign, AtKeys keys) =>
    openLock(normalizedAtSign, keys.enrollmentToAuthenticateAs());

/// Runs [open] once every open started earlier under [lock] has ended,
/// however it ended, and returns its result.
///
/// Building a client checks for a live one and registers its own across
/// awaits, so two opens running together would both pass the check. Every
/// path that builds a client for an (atSign, enrollment) queues here, so
/// they wait on each other whichever way they were started.
Future<T> queuedOpen<T>(String lock, Future<T> Function() open) =>
    _opening.run(lock, open);

/// Opens a session for [atSign] as [enrollmentId], queued behind every open
/// and teardown already running for that pair.
///
/// The live-client check runs inside the queue, after any queued teardown:
/// once it is this open's turn the pair is free or a session is live, and a
/// live one rejects with [SessionAlreadyOpenException] instead of reaching
/// at_client's untyped refusal.
Future<T> queuedSessionOpen<T>(
        String atSign, String enrollmentId, Future<T> Function() open) =>
    queuedOpen(openLock(atSign, enrollmentId), () {
      if (AtClientImpl.holdsLiveClientAs(atSign, enrollmentId)) {
        throw SessionAlreadyOpenException(atSign);
      }
      return open();
    });

/// The opens running for each lock; it never completes with an error.
final _opening = KeyedQueue<String>();
