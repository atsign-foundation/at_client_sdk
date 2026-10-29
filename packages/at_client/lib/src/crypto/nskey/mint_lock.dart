import 'dart:async' show Completer, unawaited;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/server_mutex.dart';
import 'package:at_commons/at_commons.dart' show AtKey, StoppedException;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('MintLock');

/// Serialises minting a key record between an atSign's own clients, two
/// processes of one enrollment among them.
///
/// The records this guards are mutable, so the interlock cannot be their own
/// immutability: it is a server mutex, a separate short-ttl immutable self key
/// whose creation the atServer refuses to repeat. Each record composes its own
/// lock key and hands it here, ttl and all.
///
/// The winner carries its [ServerMutexLease] into its critical section and
/// refuses to publish once it is spent. The election bounds when clients
/// attempt, not how long the winner takes, so a holder that overran the ttl
/// would publish on top of the client that legitimately won the next one.
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
  /// so a caller on another ring meets the wire lock instead, and is refused
  /// like any other client.
  final Map<String, Future<void>> _inFlight = {};

  MintLock(this.atClient);

  /// Runs [mint] holding [lockKey], and returns its result.
  ///
  /// Returns null when the lock cannot be taken, without waiting — so a caller
  /// whose [mint] can itself return null should return something non-null from
  /// it, or the two answers become one.
  ///
  /// The winner never releases the lock; the ttl does. So "held" does not mean
  /// another client is minting, and nothing here reads the lock's value to
  /// tell: every refusal is contention, whichever client took the lock. A
  /// client that took it and stopped before publishing is refused on its next
  /// start until the ttl runs out. That release depends on an atServer which
  /// stops refusing a create once the record has expired; one that keeps
  /// refusing makes the cooldown permanent.
  Future<T?> withLock<T>(
      AtKey lockKey, Future<T> Function(ServerMutexLease lease) mint) async {
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
      final (lease, refused) = await _take(lockKey, ttl);
      if (lease == null) {
        _logger.info('Could not take $lockKey, so nothing is minted under it '
            'this time: $refused');
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

  /// Takes [lockKey] for [ttl], and returns the lease, or else why it could
  /// not be taken.
  Future<(ServerMutexLease?, Object?)> _take(
      AtKey lockKey, Duration ttl) async {
    try {
      final lease = await atClient.tryAcquireServerMutex(lockKey, ttl: ttl);
      return (lease, lease == null ? 'its record already exists' : null);
    } catch (e) {
      // NOTE: an Error is a mistake in the call, such as a ttl over the cap,
      // not a reason the lock was unavailable.
      if (e is StoppedException || e is Error) rethrow;
      // NOTE: any failure to take the lock is as much a reason not to mint as
      // the lock being held.
      return (null, e);
    }
  }
}
