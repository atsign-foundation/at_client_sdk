import 'package:at_client/at_client.dart';

import '../collections/js_collections_adapter.dart' show maxItemDataDepth;
import '../exceptions.dart';
import '../log_text.dart';

// The one place an exception becomes an error code and a message for JS.
// Both are pure functions of the thrown type and its structured fields: no
// exception's own text ever chooses a code, and the bridge authors every
// message JS sees. The only text it passes through from an exception is the id
// refusal AtCollection words itself (CollectionRefusal.itemId) and the id and
// owner an error carries, each bounded by [boundedRejectionText]; every other
// message is fixed here or built from structured fields.

/// The `AtError.code` for [error]: one string per typed exception the
/// session layer throws, a `COLLECTION_*` code for a collection failure, and
/// `internal` for anything else.
String errorCodeOf(Object error) => switch (error) {
      InvalidArgumentException() => 'invalid_argument',
      JsCollectionsError(:final kind) => collectionErrorCode(kind),
      AtOpenRefusedException() => 'pkam_refused',
      PortalSessionOfflineException() => 'offline',
      AtEnrollmentPendingException() => 'onboarding_incomplete',
      EnrollmentConveyanceException() => 'enrollment_conveyance_failed',
      EnrollmentInFlightException() => 'enrollment_in_flight',
      AtEnrollmentException() => 'enrollment_denied',
      SessionClosedException() || StoppedException() => 'closed',
      UnsupportedKeyMaterialException() ||
      UnsupportedOperationException() ||
      UnsupportedError() ||
      ManageAccessRequiredException() =>
        'unsupported',
      InvalidKeyException() ||
      AtNoCredentialException() ||
      InvalidAtSignException() =>
        'bad_key',
      _ => 'internal',
    };

/// The `COLLECTION_*` code for a collection failure of [kind].
String collectionErrorCode(CollectionFailure kind) => switch (kind) {
      CollectionFailure.invalidArgument => 'COLLECTION_INVALID_ARGUMENT',
      CollectionFailure.notFound => 'COLLECTION_ITEM_NOT_FOUND',
      CollectionFailure.notOwner => 'COLLECTION_ITEM_NOT_OWNER',
      CollectionFailure.alreadyExists => 'COLLECTION_ITEM_ALREADY_EXISTS',
      CollectionFailure.hasSubItems => 'COLLECTION_ITEM_HAS_SUB_ITEMS',
      CollectionFailure.unreadable => 'COLLECTION_ITEM_UNREADABLE',
      CollectionFailure.typeMismatch => 'COLLECTION_TYPE_MISMATCH',
      CollectionFailure.wrongType => 'COLLECTION_ITEM_WRONG_TYPE',
      CollectionFailure.partialFailure => 'COLLECTION_PARTIAL_FAILURE',
      CollectionFailure.failed => 'COLLECTION_FAILED',
      CollectionFailure.tooDeep => 'COLLECTION_ITEM_TOO_DEEP',
    };

/// The message JS sees for [error]: fixed here, or built from the exception's
/// fields, each echoed field bounded to one line. A message names a parameter
/// and never its value.
String atErrorMessage(Object error) => switch (error) {
      InvalidArgumentException() => _argumentMessage(error),
      JsCollectionsError() => _collectionMessage(error),
      AtOpenRefusedException(:final state) =>
        'the atServer refused the session (${state.cause?.name ?? 'refused'})',
      PortalSessionOfflineException(:final state) =>
        'the session could not reach the atServer (${state.cause?.name ?? 'offline'})',
      AtEnrollmentPendingException() =>
        'onboarding is incomplete: no usable credential',
      EnrollmentConveyanceException(:final keyPackageStatus) =>
        'enrollment approved on server, but key conveyance failed (${keyPackageStatus.name})',
      EnrollmentInFlightException() => enrollmentInFlightMessage,
      AtEnrollmentException() =>
        'the enrollment request was denied or is not pending',
      SessionClosedException() || StoppedException() => sessionClosedMessage,
      UnsupportedKeyMaterialException() =>
        'the keys carry unsupported cryptographic material',
      ManageAccessRequiredException() => manageAccessRequiredMessage,
      UnsupportedOperationException(:final operation) => switch (operation) {
          UnsupportedOperation.secureContext =>
            'a secure context (HTTPS) is required',
        },
      // An UnsupportedError maps by type alone: its text is never read or
      // shown, whoever raised it (the setup lock's included).
      UnsupportedError() => 'the operation is not supported here',
      InvalidKeyException() => _keyMessage(error),
      AtNoCredentialException() => 'keys hold no usable credential',
      InvalidAtSignException() => 'atSign is not valid',
      _ => 'internal error',
    };

/// [value] on one line and at most [maxErrorMessageLength] long: the one bound
/// every message and every echoed rejection field shares, so a peer-chosen id
/// or owner cannot carry control characters or unbounded text into JS.
String boundedRejectionText(String value) =>
    truncateText(singleLine(value), maxErrorMessageLength);

/// What each parameter the session validates by itself has to be, for an
/// [InvalidArgumentException] that names no `expected`. The namespace is not
/// here: the opener refuses it as an [ArgumentError] and the bridge words it.
const _expectedOf = {
  'regex': 'a valid regular expression',
};

String _keyMessage(InvalidKeyException error) =>
    boundedRejectionText(switch (error) {
      InvalidKeyException(:final field?) => _argumentMessage(field),
      InvalidKeyException(:final refusal) => switch (refusal) {
          KeyRefusal.publicKey => 'public keys cannot be sent with notify',
          KeyRefusal.cachedKey => 'cached keys cannot be sent with notify',
          KeyRefusal.sharedWithMissing => 'notify needs sharedWith',
          KeyRefusal.sharedWithInvalid => 'sharedWith must be a valid atSign',
          KeyRefusal.sharedByInvalid => 'sharedBy must be a valid atSign',
          KeyRefusal.sharedByMismatch =>
            'sharedBy must match the session atSign',
          KeyRefusal.keyName => 'key is not a valid key name',
          KeyRefusal.namespace => 'namespace is not valid',
          KeyRefusal.atKey => 'key is not a valid atKey',
          KeyRefusal.keysJson => 'keys is not valid JSON',
          KeyRefusal.keysDocument => 'keys is not a usable .atKeys document',
          KeyRefusal.field => 'key is not valid',
        },
    });

String _argumentMessage(InvalidArgumentException error) {
  final name = error.parameter;
  if (error.missing) return boundedRejectionText('$name must not be null');
  final expected = error.expected ?? _expectedOf[error.parameter] ?? 'valid';
  return boundedRejectionText('$name must be $expected');
}

String _collectionMessage(JsCollectionsError error) {
  final id = _token(error.id ?? '');
  final owner = _atSign(error.owner);
  return boundedRejectionText(switch (error.kind) {
    CollectionFailure.invalidArgument => _refusalMessage(error),
    CollectionFailure.notFound => 'item not found',
    CollectionFailure.notOwner =>
      'item $id is owned by $owner, not ${_atSign(error.collectionOwner)}',
    CollectionFailure.alreadyExists => 'item already exists',
    CollectionFailure.hasSubItems => 'item has sub-items',
    CollectionFailure.unreadable => error.owner == null
        ? 'item $id could not be read'
        : 'item $id owned by $owner could not be read',
    CollectionFailure.typeMismatch =>
      'a where clause compared values of different types',
    CollectionFailure.wrongType =>
      'item $id is a ${_token(error.foundType ?? '')}, '
          'not a ${_token(error.expectedType ?? '')}',
    CollectionFailure.partialFailure =>
      '${error.failures.length} key-level write(s) failed',
    CollectionFailure.failed => 'operation failed',
    CollectionFailure.tooDeep =>
      'item data nests deeper than $maxItemDataDepth levels',
  });
}

String _refusalMessage(JsCollectionsError error) {
  final subject = _token(error.subject ?? '');
  return switch (error.refusal) {
    CollectionRefusal.collectionName =>
      'collection name must be a valid key name',
    CollectionRefusal.type => 'type must be a non-empty string',
    CollectionRefusal.expiration => 'expirationMs must be > 0',
    CollectionRefusal.eventSource => 'unknown eventSource $subject',
    CollectionRefusal.wherePath => 'empty segment in where path $subject',
    CollectionRefusal.whereOperator => 'unknown where operator $subject',
    CollectionRefusal.whereValue =>
      'where $subject needs a number or string value',
    CollectionRefusal.atSign => 'invalid atSign',
    CollectionRefusal.itemId => error.subject ?? 'invalid argument',
    CollectionRefusal.typeTag =>
      'collection is already open with a different type',
    null => 'invalid argument',
  };
}

/// [atSign] on one line; an atSign is validated where it is built.
String _atSign(String? atSign) => singleLine(atSign ?? '');

/// [value] as one quoted token of at most 64 characters, control and
/// direction characters escaped.
String _token(String value) => sanitizeLogText(value, maxLength: 64);
