import 'dart:convert';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

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
  /// lock in elapsed time. One read back from the record ends at the atServer's
  /// expiry, judged on this client's clock, so a client clock behind the
  /// atServer's extends it, but never beyond a fresh lease's length from the
  /// read. Neither is a fence: a write sent just before [isSpent] turns can land
  /// after the lock expired.
  final DateTime expiresAt;

  final Stopwatch _held;
  final Duration _length;

  /// A lease on [key] that ends at [expiresAt], counted from now in elapsed
  /// time.
  ServerMutexLease(this.key, this.expiresAt)
      : _held = Stopwatch()..start(),
        _length = expiresAt.difference(DateTime.now());

  ServerMutexLease._(this.key, this.expiresAt, this._held, this._length);

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
  /// Takes the lock [key] names for [ttl], or returns null when its record
  /// already exists.
  ///
  /// That record may be another client's lock, or one this client took within
  /// its ttl. [key] must be a self key of this client's atSign, and is used as
  /// given: no namespace is added to it. [ttl] must be at least a millisecond
  /// and no longer than [maxServerMutexTtl]; either mistake throws an
  /// [ArgumentError] before anything is sent.
  ///
  /// Every failure other than the record existing is thrown, so the caller
  /// decides whether to go ahead without the lock. A failure such as a timeout
  /// can come after the atServer stored the record, and the lock then stays
  /// held until its ttl runs out.
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
    return ServerMutexLease._(record, leaseFrom.add(ttl), held, ttl);
  }
}

/// Reading a server mutex back, for at_client's own use.
///
/// A lock records the enrollment that took it, and every client with no
/// enrollment records the primary sentinel. So two clients under one
/// enrollment, and any two clients with no enrollment, cannot be told apart:
/// each sees the other's lock as its own.
extension ServerMutexHolder on AtClient {
  /// Whether the lock [key] names is held under this client's enrollment.
  ///
  /// [key] must be a self key of this client's atSign. A lock that does not
  /// exist is not held; any other failure to read it is thrown.
  Future<bool> holdsServerMutex(AtKey key) async {
    final lock = await _readLock(this, key);
    return lock != null && lock.holder == _holderOf(this);
  }

  /// A lease on the lock [key] names when this client's enrollment already
  /// holds it; otherwise null.
  ///
  /// It ends at the record's own expiry, or [ttl] after the read began if that
  /// is sooner, so it is never longer than a fresh lease. It can still outlast
  /// the lock: the expiry is the atServer's, read on this client's clock, and
  /// a client clock behind the atServer's extends the lease by the difference,
  /// up to [ttl]. The atServer's own time is not available to correct for
  /// that, so a caller re-reads what it guards before writing rather than
  /// relying on the lease to exclude. Null too when the record carries no
  /// expiry, since a lease must end no later than its lock.
  /// [ttl] is checked as [ServerMutex.tryAcquireServerMutex] checks it.
  Future<ServerMutexLease?> ownServerMutexLease(AtKey key,
      {required Duration ttl}) async {
    checkedServerMutexTtl(ttl, 'ttl');
    final cap = DateTime.now().toUtc().add(ttl);
    final lock = await _readLock(this, key);
    if (lock == null || lock.holder != _holderOf(this)) return null;
    final expiresAt = lock.expiresAt;
    if (expiresAt == null) return null;
    return ServerMutexLease(
        lock.record, expiresAt.isBefore(cap) ? expiresAt : cap);
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

/// This client's identity in a lock record: its enrollment, or the primary
/// sentinel for a client with none.
String _holderOf(AtClient client) =>
    client.enrollmentId ?? EnrollmentConstants.primaryEnrollmentId;

/// The lock record [key] names, its holder and its expiry, read in one lookup;
/// null when it does not exist.
Future<({AtKey record, String holder, DateTime? expiresAt})?> _readLock(
    AtClient client, AtKey key) async {
  final record = _lockRecord(client, key);
  final String response;
  try {
    response =
        await client.getRemoteSecondary()!.executeVerb(LLookupVerbBuilder()
          ..atKey = record
          ..operation = 'all');
  } on KeyNotFoundException {
    return null;
  }
  final stored = jsonDecode(response.replaceFirst('data:', ''));
  if (stored is! Map<String, dynamic>) {
    throw FormatException(
        'not a record from llookup:all for $record', response);
  }
  final metadata = stored['metaData'];
  final expiresAt = metadata is Map ? metadata['expiresAt'] : null;
  return (
    record: record,
    holder: '${stored['data']}'.trim(),
    expiresAt:
        expiresAt == null ? null : DateTime.tryParse('$expiresAt')?.toUtc(),
  );
}

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
