import 'package:at_client/at_client.dart';

// Every exception this package throws is declared here and is an
// [AtException], so a Dart caller can catch the family with one `on`. The
// file reaches no web-only API. Only the JS bridge turns one into an error
// code or a message for JS (lib/src/js/error_codes.dart).

/// Thrown when the caller passed something the call cannot use: a missing or
/// mistyped option, a value that does not parse, a callback that is not a
/// function.
///
/// [message] names the parameter and never holds its value. [id] is the item
/// id an address names, for the one rejection that reports it.
class InvalidArgumentException extends AtException {
  InvalidArgumentException(super.message, {this.id});

  /// The item id the rejected address named, folded to lower case.
  final String? id;

  @override
  String toString() => 'InvalidArgumentException: $message';
}

/// Thrown by a session, or by a collection it opened, when a call arrives
/// after the session was closed. at_client's `StoppedException` never reaches
/// the caller of a closed session: it is this, an [AtException].
class SessionClosedException extends AtException {
  SessionClosedException() : super('the session is closed');

  @override
  String toString() => 'SessionClosedException: $message';
}

/// Thrown when a `NotifyKey` cannot do what was asked of it, such as a notify
/// with no `sharedWith`.
class InvalidKeyException extends AtException {
  InvalidKeyException(this.reason) : super(reason);

  final String reason;

  @override
  String toString() => 'InvalidKeyException: $reason';
}

/// Thrown by the pairing calls of a session that holds no `__manage`, which
/// only the atServer's roster-managing enrollments do.
class ManageAccessRequiredException extends AtException {
  ManageAccessRequiredException()
      : super('this session cannot manage enrollments');

  @override
  String toString() =>
      'ManageAccessRequiredException: this session cannot manage enrollments';
}

/// Thrown by an approve or deny of an enrollment whose first decision has
/// not settled. It is an [AtEnrollmentException] to a Dart caller, and
/// names neither the atSign nor the enrollment id.
class EnrollmentInFlightException extends AtEnrollmentException {
  EnrollmentInFlightException()
      : super('a decision for this request is already in flight');

  @override
  String toString() => 'EnrollmentInFlightException: $message';
}

/// Thrown by `portalSession` when the client did not come online.
class SessionOfflineException extends AtException {
  final String atSign;

  /// The connection state the open ended in.
  final AtConnectionState state;

  SessionOfflineException(this.atSign, this.state)
      : super('$atSign did not come online (${state.cause?.name})');

  @override
  String toString() => 'SessionOfflineException: $message';
}

/// Thrown by `portalSession` for keys that carry ML-DSA-65 signing or
/// namespace key material.
///
/// This is a stopgap: a session's key store is in memory, so a client that
/// raised its posture on such keys would file new material nowhere that
/// survives. The passkey-onboarding gate replaces this check.
class UnsupportedKeyMaterialException extends AtException {
  final String atSign;

  UnsupportedKeyMaterialException(this.atSign)
      : super('the keys for $atSign carry ML-DSA-65 signing or namespace key '
            'material, which a session with an in-memory key store cannot '
            'hold');

  @override
  String toString() => 'UnsupportedKeyMaterialException: $message';
}

/// Thrown when the lock named [lockName] is not granted within the
/// acquisition timeout.
class SetupLockTimeoutException extends AtException {
  /// Creates the exception for [lockName].
  SetupLockTimeoutException(this.lockName) : super('$lockName was not granted');

  /// The name of the lock that was not granted.
  final String lockName;

  @override
  String toString() => 'SetupLockTimeoutException: $lockName was not granted';
}

/// Thrown when IndexedDB refuses an operation of the passkey stores.
///
/// The message names the browser's error, such as `QuotaExceededError`, when
/// the browser gave one, and never holds a stored value.
class IndexedDbException extends AtException {
  /// Creates the exception with [message].
  IndexedDbException(super.message);

  @override
  String toString() => 'IndexedDbException: $message';
}

/// Why a collection operation failed. The bridge maps each kind to one code.
enum CollectionFailure {
  /// A malformed argument the adapter or AtCollection refused.
  invalidArgument,

  /// No item with that id and owner.
  notFound,

  /// A write to an item owned by another atSign.
  notOwner,

  /// A create with an id that already exists.
  alreadyExists,

  /// A remove without cascade of an item that has sub-items.
  hasSubItems,

  /// A record this device cannot read.
  unreadable,

  /// An ordering `where` met a value of another type at its path.
  typeMismatch,

  /// An update of an item another type tag wrote.
  wrongType,

  /// Some key-level writes of one operation failed.
  partialFailure,

  /// Any other failure; [CollectionException.causeType] names it.
  failed,

  /// An item whose data nests deeper than the adapter allows.
  tooDeep,
}

/// The single error shape every collection adapter operation rejects with.
///
/// It carries a [kind] and no error code: the bridge maps the kind. The
/// [message] is the bounded detail the adapter knows (an unknown
/// eventSource, the id text AtCollection refused); the bridge decides what
/// reaches JS.
final class CollectionException extends AtException {
  CollectionException(
    this.kind,
    super.message, {
    this.id,
    this.owner,
    this.causeType,
    this.failures = const [],
  });

  final CollectionFailure kind;

  /// The item the failure is about, when known.
  final String? id;
  final String? owner;

  /// The Dart type of the underlying error, for [CollectionFailure.failed]
  /// and each [failures] entry: a name the adapter knows, or `'Unknown'`.
  final String? causeType;

  /// For [CollectionFailure.partialFailure]: one `{op, recipient, kind}` per
  /// failed key-level write, where recipient is the atSign the copy was for.
  final List<Map<String, String>> failures;

  @override
  String toString() => 'CollectionException(${kind.name}): $message';
}
