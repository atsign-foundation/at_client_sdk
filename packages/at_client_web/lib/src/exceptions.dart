import 'package:at_client/at_client.dart';

// Every exception this package declares lives here and extends
// [AtException], so a Dart caller can catch the family with one `on`.
// Exceptions it throws from at_client keep their own types, such as
// [AtEnrollmentException] and [StoppedException]. The file reaches no
// web-only API. Only the JS bridge turns one into an error code or a message
// for JS (lib/src/js/error_codes.dart).

/// What a closed session rejects with, to Dart and to JS alike.
const sessionClosedMessage = 'the session is closed';

/// What a session without `__manage` rejects a pairing call with.
const manageAccessRequiredMessage = 'this session cannot manage enrollments';

/// What an approve or deny of an enrollment with an unsettled first decision
/// rejects with.
const enrollmentInFlightMessage =
    'a decision for this request is already in flight';

/// The longest message an `invalid_argument` or collection rejection carries.
const maxErrorMessageLength = 128;

/// The longest notification key the session delivers, counted in UTF-16 code
/// units. A safety bound, not validity: a longer key is dropped unparsed.
const maxNotificationKeyLength = 255;

/// [id] folded to lower case, as AtCollection folds an item id. Exceptions
/// and the adapter's per-item lock take their ids through this one fold.
String foldItemId(String id) => id.toLowerCase();

/// Thrown when the caller passed something the call cannot use: a missing or
/// mistyped option, a value that does not parse, a callback that is not a
/// function.
///
/// It carries the [parameter] and what it [expected], never the value and
/// never finished text: the bridge words what JS sees from these fields
/// (lib/src/js/error_codes.dart). [id] is the item id an address names, for
/// the one rejection that reports it.
class InvalidArgumentException extends AtException {
  /// [parameter] was not usable. [expected] is what it had to be (`a string`);
  /// left out, the bridge words it from [parameter].
  InvalidArgumentException(this.parameter, {this.expected, String? id})
      : missing = false,
        id = id == null ? null : foldItemId(id),
        super('$parameter must be ${expected ?? 'valid'}');

  /// [parameter] was null or absent.
  InvalidArgumentException.missing(this.parameter)
      : expected = null,
        missing = true,
        id = null,
        super('$parameter must not be null');

  /// The name of the rejected parameter.
  final String parameter;

  /// What [parameter] had to be, or null.
  final String? expected;

  /// Whether [parameter] was null or absent.
  final bool missing;

  /// The item id the rejected address named, folded to lower case.
  final String? id;

  @override
  String toString() => 'InvalidArgumentException: $message';
}

/// Thrown by a session, or by a collection it opened, when a call arrives
/// after the session was closed. at_client's `StoppedException` never reaches
/// the caller of a closed session: it is this, an [AtException].
class SessionClosedException extends AtException {
  SessionClosedException() : super(sessionClosedMessage);

  @override
  String toString() => 'SessionClosedException: $message';
}

/// What the page or browser lacks, for an [UnsupportedOperationException].
/// The bridge words each one (lib/src/js/error_codes.dart).
enum UnsupportedOperation { secureContext }

/// Thrown when the page or browser cannot do what a call needs.
class UnsupportedOperationException extends AtException {
  /// What is missing.
  final UnsupportedOperation operation;

  /// Creates the exception for [operation].
  UnsupportedOperationException(this.operation) : super(operation.name);

  @override
  String toString() => 'UnsupportedOperationException: ${operation.name}';
}

/// What was wrong with a key or a `.atKeys` document, for an
/// [InvalidKeyException]. The bridge words each one (lib/src/js/error_codes.dart).
enum KeyRefusal {
  /// A notify key with `public: true`.
  publicKey,

  /// A notify key with `cached: true`.
  cachedKey,

  /// A notify key with no `sharedWith`.
  sharedWithMissing,

  /// A notify key whose `sharedWith` is not an atSign.
  sharedWithInvalid,

  /// A notify key whose `sharedBy` is not an atSign.
  sharedByInvalid,

  /// A notify key whose `sharedBy` is not the session's atSign.
  sharedByMismatch,

  /// A notify key that does not make a valid atKey.
  atKey,

  /// A `.atKeys` document given as text that is not JSON.
  keysJson,

  /// A `.atKeys` document that is not usable.
  keysDocument,

  /// A key field of the wrong shape; [InvalidKeyException.field] names it.
  field,
}

/// Thrown when atKey text or a `.atKeys` document cannot do what was
/// asked of it, such as notify text with no recipient.
///
/// It carries a [refusal], never finished text: the bridge words what JS sees.
class InvalidKeyException extends AtException {
  InvalidKeyException(this.refusal)
      : field = null,
        super(refusal.name);

  /// A key field of the wrong shape: [field] names the parameter and what it
  /// had to be.
  InvalidKeyException.field(InvalidArgumentException this.field)
      : refusal = KeyRefusal.field,
        super(field.message);

  final KeyRefusal refusal;

  /// The mistyped field, for [KeyRefusal.field].
  final InvalidArgumentException? field;

  @override
  String toString() => 'InvalidKeyException: ${refusal.name}';
}

/// Thrown by the pairing calls of a session that holds no `__manage`, which
/// only the atServer's roster-managing enrollments do.
class ManageAccessRequiredException extends AtException {
  ManageAccessRequiredException() : super(manageAccessRequiredMessage);

  @override
  String toString() =>
      'ManageAccessRequiredException: $manageAccessRequiredMessage';
}

/// Why a `notify` failed, for a [NotifyFailedException]. The
/// bridge words each one; none carries an at_client message.
enum NotifyFailure {
  /// Sending the notification failed.
  sendFailed,

  /// The atServer could not be reached.
  offline,

  /// The atServer did not answer in time.
  timeout,
}

/// Thrown when a notify failed: sending it failed, or the atServer could not
/// be reached or did not answer in time.
///
/// It carries a [kind], never finished text: the bridge words what JS sees
/// (lib/src/js/error_codes.dart).
class NotifyFailedException extends AtException {
  /// Creates the exception for [kind].
  NotifyFailedException(this.kind) : super(kind.name);

  /// What the failure was.
  final NotifyFailure kind;

  @override
  String toString() => 'NotifyFailedException: ${kind.name}';
}

/// Thrown by an approve or deny of an enrollment whose first decision has
/// not settled. It is an [AtEnrollmentException] to a Dart caller, and
/// names neither the atSign nor the enrollment id.
class EnrollmentInFlightException extends AtEnrollmentException {
  EnrollmentInFlightException() : super(enrollmentInFlightMessage);

  @override
  String toString() => 'EnrollmentInFlightException: $message';
}

/// Thrown by `portalSession` when the client did not come online.
class PortalSessionOfflineException extends AtException {
  final String atSign;

  /// The connection state the open ended in.
  final AtConnectionState state;

  PortalSessionOfflineException(this.atSign, this.state)
      : super('$atSign did not come online (${state.cause?.name})');

  @override
  String toString() => 'PortalSessionOfflineException: $message'
      '${state.error == null ? '' : ': ${state.error}'}';
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
            'material, which a session with an in-memory AtKeys store cannot '
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

  /// Any other failure; [JsCollectionsError.causeType] names it.
  failed,

  /// An item whose data nests deeper than the adapter allows.
  tooDeep,
}

/// What a [CollectionFailure.invalidArgument] refused. The bridge words each
/// from [JsCollectionsError.subject].
enum CollectionRefusal {
  /// The collection name is not a valid key name.
  collectionName,

  /// The collection type is blank.
  type,

  /// `expirationMs` is not positive.
  expiration,

  /// The eventSource is not `data`, `notifs` or `both`; the subject is it.
  eventSource,

  /// A `where` path has an empty segment; the subject is the path.
  wherePath,

  /// A `where` operator is unknown; the subject is it.
  whereOperator,

  /// A `where` ordering operator met a value that is neither a number nor a
  /// string; the subject is the operator.
  whereValue,

  /// An atSign AtCollection refused.
  atSign,

  /// An item id AtCollection refused; the subject is AtCollection's own text
  /// for it.
  itemId,

  /// The collection is already open with another type tag.
  typeTag,
}

/// The single error shape every collection adapter operation rejects with.
///
/// It carries a [kind] and structured fields, and neither an error code nor
/// finished text: the bridge maps the kind to a code and words the message
/// from the fields (lib/src/js/error_codes.dart). [message] is a terse
/// Dart-side description for a Dart caller.
final class JsCollectionsError extends AtException {
  JsCollectionsError(
    this.kind, {
    this.refusal,
    this.subject,
    String? id,
    this.owner,
    this.collectionOwner,
    this.foundType,
    this.expectedType,
    this.causeType,
    this.failures = const [],
  })  : id = id == null ? null : foldItemId(id),
        super(subject != null && refusal == CollectionRefusal.itemId
            ? subject
            : refusal == null
                ? kind.name
                : '${kind.name} (${refusal.name})');

  final CollectionFailure kind;

  /// For [CollectionFailure.invalidArgument]: what was refused.
  final CollectionRefusal? refusal;

  /// The raw token [refusal] names, such as the unknown operator.
  final String? subject;

  /// The item the failure is about, when known, folded to lower case.
  final String? id;
  final String? owner;

  /// For [CollectionFailure.notOwner]: the atSign the collection belongs to.
  final String? collectionOwner;

  /// For [CollectionFailure.wrongType]: the type tag the item carries.
  final String? foundType;

  /// For [CollectionFailure.wrongType]: the type tag the write asked for.
  final String? expectedType;

  /// The Dart type of the underlying error, for [CollectionFailure.failed]
  /// and each [failures] entry: a name the adapter knows, or `'Unknown'`.
  final String? causeType;

  /// For [CollectionFailure.partialFailure]: one `{op, recipient, kind}` per
  /// failed key-level write, where recipient is the atSign the copy was for.
  final List<Map<String, String>> failures;

  @override
  String toString() => 'JsCollectionsError(${kind.name}): $message';
}
