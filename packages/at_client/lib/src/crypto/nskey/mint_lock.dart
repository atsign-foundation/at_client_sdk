import 'dart:async' show Completer, unawaited;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/server_mutex.dart';
import 'package:at_commons/at_commons.dart' show AtKey, StoppedException;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('MintLock');

/// Serialises minting a key record between an atSign's own enrollments.
///
/// The records this guards are mutable, so the interlock cannot be their own
/// immutability: it is a server mutex, a separate short-ttl immutable self key
/// whose creation the atServer refuses to repeat. Each record composes its own
/// lock key and hands it here, ttl and all.
///
/// The winner carries its [ServerMutexLease] into its critical section and
/// refuses to publish once it is spent. The election bounds when enrollments
/// attempt, not how long the winner takes, so a holder that overran the ttl
/// would publish on top of the enrollment that legitimately won the next one.
///
/// A lock is a protocol, not a guarantee — it narrows a window to the ttl, so
/// every caller still reconciles what it holds against what is published rather
/// than trusting that holding the lock made it the only writer.
@experimental
class MintLock {
  final AtClient atClient;

  /// Mints running against this `MintLock` instance right now, keyed by lock
  /// record.
  ///
  /// Instance, not process: a `MintLock` is built per [PublishedNskeyKeyRing],
  /// so callers that do not share a ring are not guarded against each other.
  /// The wire lock cannot express this — its value is the enrolment id, an
  /// identity rather than an instance, so two racers of the same enrolment each
  /// read it back, see their own id, and conclude they hold it.
  final Map<String, Future<void>> _inFlight = {};

  MintLock(this.atClient);

  /// Runs [mint] holding [lockKey], and returns its result.
  ///
  /// Returns null when the lock is already held, without waiting — so a caller
  /// whose [mint] can itself return null should return something non-null from
  /// it, or the two answers become one.
  ///
  /// The winner never releases the lock; the ttl does. So "held" does not mean
  /// another enrollment is minting: a client that took the lock and exited
  /// before publishing loses to its own token for the rest of the ttl, and
  /// unless [ownLockIsNotContention] is set nothing here reads the lock's value
  /// to tell the two apart. That release depends on an atServer which stops
  /// refusing a create once the record has expired; one that keeps refusing
  /// makes the cooldown permanent.
  ///
  /// [ownLockIsNotContention] lets a caller whose critical section is
  /// idempotent proceed when the lock it meets is one this same enrollment took
  /// earlier in the cooldown. It is off by default because rotation is not
  /// idempotent, and rate-limiting it is what holding the lock for the full ttl
  /// is for; a caller that opts in must read what is published before writing.
  Future<T?> withLock<T>(
      AtKey lockKey, Future<T> Function(ServerMutexLease lease) mint,
      {bool ownLockIsNotContention = false}) async {
    // NOTE: declining rather than returning the winner's result keeps one
    // meaning for a null — "you did not mint".
    final inFlightKey = lockKey.toString();
    final running = _inFlight[inFlightKey];
    if (running != null) {
      _logger.info('A mint for $lockKey is already in flight in this process; '
          'waiting for it rather than racing it, then re-reading');
      await running;
      return null;
    }

    final ttlMillis = lockKey.metadata.ttl;
    if (ttlMillis == null || ttlMillis <= 0) {
      throw ArgumentError.value(
          ttlMillis,
          'lockKey.metadata.ttl',
          'a mint lock needs a ttl: it is released by expiry and by nothing '
              'else, so without one $lockKey would block minting permanently');
    }
    final done = Completer<void>();
    _inFlight[inFlightKey] = done.future;
    try {
      final ttl = Duration(milliseconds: ttlMillis);
      // NOTE: stamped before the request goes out, as a won lease is.
      final leaseFrom = DateTime.now();
      final lease = await _take(lockKey, ttl) ??
          (ownLockIsNotContention && await _isOwnLock(lockKey)
              ? ServerMutexLease(lockKey, leaseFrom.add(ttl))
              : null);
      if (lease == null) {
        _logger.info('$lockKey is already held; re-reading rather than '
            'waiting for it. Whether the holder is another enrollment or '
            'this one from an earlier run was not established');
        return null;
      }
      return await mint(lease);
    } finally {
      // NOTE: released only once the mint has published, so a waiter that wakes
      // here re-reads an advertisement that is already on the atServer.
      unawaited(_inFlight.remove(inFlightKey));
      done.complete();
    }
  }

  /// Takes [lockKey] for [ttl], or returns null when it was not taken.
  Future<ServerMutexLease?> _take(AtKey lockKey, Duration ttl) async {
    try {
      return await atClient.tryAcquireServerMutex(lockKey, ttl: ttl);
    } catch (e) {
      if (e is StoppedException) rethrow;
      // NOTE: any failure to take the lock is as much a reason not to mint as
      // the lock being held.
      _logger.finer('Could not take $lockKey: $e');
      return null;
    }
  }

  /// Whether the lock that refused us is one this enrollment already holds.
  ///
  /// The winner never releases — the ttl does — so a client that mints and then
  /// re-enters within the cooldown loses the election to itself; the cooldown
  /// covers an ordinary restart. Proceeding is safe only because every caller
  /// reads what is published before minting, and a read that cannot say whose
  /// lock it is answers false.
  Future<bool> _isOwnLock(AtKey lockKey) async {
    try {
      if (!await atClient.holdsServerMutex(lockKey)) return false;
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.finer('Could not read $lockKey to check ownership: $e');
      return false;
    }
    _logger.info('$lockKey is this enrollment\'s own lock, taken earlier in '
        'its cooldown — proceeding rather than treating ourselves as a '
        'loser');
    return true;
  }
}
