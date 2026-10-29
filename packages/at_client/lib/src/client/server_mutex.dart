import 'dart:math' show Random;

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart';

/// The longest a server mutex may be held.
const Duration maxServerMutexTtl = Duration(minutes: 15);

/// A server mutex this client took, valid until [expiresAt].
class ServerMutexLease {
  /// The record the lock is held on.
  final AtKey key;

  /// When this lease stops being valid, by this client's wall clock as it read
  /// when the lease was made.
  ///
  /// A lease from [ServerMutex.tryAcquireServerMutex] ends no later than the
  /// lock in elapsed time. It is not a fence: a write sent just before
  /// [isSpent] turns can land after the lock expired.
  final DateTime expiresAt;

  final Stopwatch _held;
  final Duration _length;

  /// A lease on [key] that ends at [expiresAt], counted from now in elapsed
  /// time.
  ServerMutexLease(this.key, this.expiresAt)
      : _held = Stopwatch()..start(),
        _length = expiresAt.difference(DateTime.now());

  /// A lease on [key] stamped [expiresAt], spent once the stopwatch it is
  /// given has run for the length it is given.
  @visibleForTesting
  ServerMutexLease.timed(this.key, this.expiresAt, this._held, this._length);

  /// Whether the lease has run out, by the time elapsed since it was made, so
  /// a change to the wall clock neither extends nor shortens it.
  bool get isSpent => _held.elapsed >= _length;
}

/// Short-lived locks shared by every client of an atSign, held on its
/// atServer.
///
/// A lock is an immutable self record with a ttl. The atServer refuses to
/// create it a second time until the ttl runs out, so of all the clients that
/// ask for it, exactly one gets a lease. Nothing releases a lock early: its ttl
/// is the only release.
///
/// Locks are written straight to the atServer, never to the local store, and
/// with `:nc`, so they reach no client's sync.
///
/// Locks need an atServer from p3.13.0 (at_commons 5.10.0), the first to parse
/// `:nc`; an older one refuses every lock, and [tryAcquireServerMutex] throws.
/// The record stays out of the commit log from c3.16.3 and p3.16.5; between
/// p3.13.0 and those the atServer records the commit anyway. An expired lock
/// stops blocking at once from c3.16.2 and p3.16.5; before that it blocks
/// until the atServer's expiry sweep, up to about ten and a half minutes.
extension ServerMutex on AtClient {
  /// Takes the lock [key] names for [ttl], or returns null when an immutable
  /// record already exists at [key]; a mutable record there is overwritten
  /// and taken.
  ///
  /// The immutable record may be another client's lock, or one this client
  /// took within its ttl. [key] must be a self key of this client's atSign, and is used as
  /// given: no namespace is added to it. [ttl] must be at least a millisecond
  /// and no longer than [maxServerMutexTtl]; either mistake throws an
  /// [ArgumentError] before anything is sent.
  ///
  /// Every failure other than that record existing is thrown, so the caller
  /// decides whether to go ahead without the lock. A failure such as a timeout
  /// can come after the atServer stored the record, and the lock then stays
  /// held until its ttl runs out.
  ///
  /// The record's value is this client's enrollment id, or `primary` for a
  /// client with none, then a colon and a nonce drawn once per isolate, so no
  /// two processes write the same value.
  Future<ServerMutexLease?> tryAcquireServerMutex(AtKey key,
      {required Duration ttl}) async {
    checkedServerMutexTtl(ttl, 'ttl');
    final record = _lockRecord(this, key)
      ..metadata = (Metadata()
        ..immutable = true
        ..ttl = ttl.inMilliseconds);
    final held = Stopwatch()..start();
    final leaseFrom = DateTime.now();
    try {
      await getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = record
        ..value = _holderOf(this)
        ..noCommit = true);
    } on AtException catch (e) {
      if (_isHeldElsewhere(e)) return null;
      rethrow;
    }
    return ServerMutexLease.timed(record, leaseFrom.add(ttl), held, ttl);
  }
}

/// [ttl], checked as a server mutex's ttl: at least a millisecond and no
/// longer than [maxServerMutexTtl], or an [ArgumentError] naming [name].
Duration checkedServerMutexTtl(Duration ttl, String name) {
  // NOTE: the ttl travels in whole milliseconds, and 0 never expires.
  if (ttl.inMilliseconds < 1 || ttl > maxServerMutexTtl) {
    throw ArgumentError.value(
        ttl,
        name,
        'must be at least a millisecond and no longer than '
        '$maxServerMutexTtl');
  }
  return ttl;
}

/// This client's value in a lock record: its enrollment, or the primary
/// sentinel for a client with none, then [_isolateNonce].
String _holderOf(AtClient client) =>
    '${client.enrollmentId ?? EnrollmentConstants.primaryEnrollmentId}'
    ':$_isolateNonce';

/// Sixteen random bytes as hex, drawn once per isolate.
final String _isolateNonce = () {
  final random = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0')
  ].join();
}();

/// The self record [key] names, owned by [client]'s atSign.
AtKey _lockRecord(AtClient client, AtKey key) {
  final atSign = client.getCurrentAtSign()!.toAtsign();
  final Atsign owner;
  try {
    owner = key.sharedBy == null ? atSign : key.sharedBy!.toAtsign();
  } on InvalidAtSignException {
    throw ArgumentError.value(
        _named(key, atSign), 'key', 'is not owned by $atSign');
  }
  if (owner != atSign) {
    throw ArgumentError.value(
        _named(key, atSign), 'key', 'is not owned by $atSign');
  }
  if (key.sharedWith != null ||
      key.isLocal ||
      key.metadata.isPublic ||
      key.metadata.isCached ||
      key.metadata.isHidden) {
    throw ArgumentError.value(_named(key, atSign), 'key', 'must be a self key');
  }
  final record = AtKey()
    ..key = key.key
    ..namespace = key.namespace
    ..sharedBy = key.sharedBy ?? atSign;
  // NOTE: the flags above don't see a key name that itself names another
  // atSign; only the name as built does.
  if (AtKey.getKeyType(record.toString()) != KeyType.selfKey) {
    throw ArgumentError.value(_named(key, atSign), 'key', 'must be a self key');
  }
  return record;
}

/// [key] as the atServer names it, with [atSign] as its owner when it names
/// none.
String _named(AtKey key, Atsign atSign) => key.sharedBy != null
    ? '$key'
    : '${AtKey()
      ..key = key.key
      ..namespace = key.namespace
      ..sharedWith = key.sharedWith
      ..isLocal = key.isLocal
      ..metadata = key.metadata
      ..sharedBy = '$atSign'}';

/// Whether [e] is the atServer refusing to create a record that exists.
bool _isHeldElsewhere(AtException e) =>
    e.message.toLowerCase().contains('immutable records may not be updated');
