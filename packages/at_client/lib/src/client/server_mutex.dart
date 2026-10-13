import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

/// The longest a server mutex may be held.
const Duration maxServerMutexTtl = Duration(minutes: 15);

/// A server mutex this client took, valid until [expiresAt].
class ServerMutexLease {
  /// The record the lock is held on.
  final AtKey key;

  /// When this lease stops being valid.
  ///
  /// Stamped before the create was sent, and the atServer starts the ttl when
  /// it stores the record, so the lease never outlives the lock. Both ends of
  /// the comparison are this client's own clock.
  final DateTime expiresAt;

  const ServerMutexLease(this.key, this.expiresAt);

  /// Whether the lease has run out, so nothing more may be done under it.
  bool get isSpent => !DateTime.now().isBefore(expiresAt);
}

/// Short-lived locks shared by every client of an atSign, held on its
/// atServer.
///
/// A lock is an immutable self record with a ttl. The atServer refuses to
/// create it a second time until the ttl runs out, so of all the clients that
/// ask for it, exactly one gets a lease. Nothing releases a lock early: its ttl
/// is the only release.
///
/// Locks are written straight to the atServer and record no commit, so they
/// never reach the local store or any client's sync.
extension ServerMutex on AtClient {
  /// Takes the lock [key] names for [ttl], or returns null when another client
  /// holds it.
  ///
  /// [key] must be a self key of this client's atSign, and is used as given:
  /// no namespace is added to it. [ttl] must be at least a millisecond and no
  /// longer than [maxServerMutexTtl]; either mistake throws an [ArgumentError]
  /// before anything is sent. Every failure other than the lock being held is
  /// thrown, so the caller decides whether to go ahead without it.
  Future<ServerMutexLease?> tryAcquireServerMutex(AtKey key,
      {required Duration ttl}) async {
    // NOTE: the ttl travels in whole milliseconds, and 0 never expires.
    if (ttl.inMilliseconds < 1 || ttl > maxServerMutexTtl) {
      throw ArgumentError.value(
          ttl,
          'ttl',
          'must be at least a millisecond and no longer than '
              '$maxServerMutexTtl');
    }
    final record = _lockRecord(key)
      ..metadata = (Metadata()
        ..immutable = true
        ..ttl = ttl.inMilliseconds);
    final leaseFrom = DateTime.now();
    try {
      await getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = record
        ..value = _holder
        ..noCommit = true);
    } on AtException catch (e) {
      if (_isHeldElsewhere(e)) return null;
      rethrow;
    }
    return ServerMutexLease(record, leaseFrom.add(ttl));
  }

  /// Whether the lock [key] names is held under this client's enrollment.
  ///
  /// Two clients under the same enrollment cannot be told apart, so each sees
  /// the other's lock as its own. [key] must be a self key of this client's
  /// atSign. A lock that does not exist is not held; any other failure to read
  /// it is thrown.
  Future<bool> holdsServerMutex(AtKey key) async {
    final String held;
    try {
      held = await getRemoteSecondary()!
          .executeVerb(LLookupVerbBuilder()..atKey = _lockRecord(key));
    } on KeyNotFoundException {
      return false;
    }
    return held.replaceFirst('data:', '').trim() == _holder;
  }

  /// This client's identity in a lock record: its enrollment, or the primary
  /// sentinel for a client with none.
  String get _holder => enrollmentId ?? EnrollmentConstants.primaryEnrollmentId;

  /// The self record [key] names, owned by this client's atSign.
  AtKey _lockRecord(AtKey key) {
    final atSign = getCurrentAtSign()!.toAtsign();
    final Atsign owner;
    try {
      owner = key.sharedBy == null ? atSign : key.sharedBy!.toAtsign();
    } on InvalidAtSignException {
      throw ArgumentError.value('$key', 'key', 'is not owned by $atSign');
    }
    if (owner != atSign) {
      throw ArgumentError.value('$key', 'key', 'is not owned by $atSign');
    }
    if (key.sharedWith != null ||
        key.isLocal ||
        key.metadata.isPublic ||
        key.metadata.isCached ||
        key.metadata.isHidden) {
      throw ArgumentError.value('$key', 'key', 'must be a self key');
    }
    return AtKey()
      ..key = key.key
      ..namespace = key.namespace
      ..sharedBy = key.sharedBy ?? atSign;
  }

  /// Whether [e] is the atServer refusing to create a record that exists.
  static bool _isHeldElsewhere(AtException e) =>
      e.message.toLowerCase().contains('immutable records may not be updated');
}
