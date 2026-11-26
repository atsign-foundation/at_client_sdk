import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart'
    show
        PasskeyCeremonyException,
        PasskeyRecordAuthenticationException,
        PrfUnavailableException,
        UnsupportedPasskeyRecordException;
import 'package:at_client/at_client.dart';
import 'package:at_client/passkey.dart'
    show
        AtServerAtKeysWriteException,
        MissingAtKeysDocumentException,
        PasskeyLostException,
        PasskeyOnboardingIncompleteException,
        PkamRefusedException,
        PublicKeyMismatchException;
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;

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
//
// `internal` is reserved for a Dart `Error` (a StateError outside the
// documented caller misuse, a TypeError, a null-check failure) and a type
// nothing here expects. Every failure a bridge path can name has its own arm.

/// The `AtError.code` for [error]: one string per typed exception the
/// session layer throws, a `COLLECTION_*` code for a collection failure, and
/// `internal` only for a Dart `Error` or a genuinely unexpected type.
String errorCodeOf(Object error) => switch (error) {
      InvalidArgumentException() || QueueLimitException() => 'invalid_argument',
      JsCollectionsError(:final kind) => collectionErrorCode(kind),
      AtOpenRefusedException() ||
      AtCredentialRefusedException() ||
      PkamRefusedException() ||
      UnAuthenticatedException() =>
        'pkam_refused',
      PortalSessionOfflineException() ||
      SecondaryConnectException() =>
        'offline',
      // `UnAuthorizedException` is an `AtConnectException`, but the atServer
      // answered: it refused the request, so it is not a connectivity failure.
      UnAuthorizedException() => 'refused',
      AtCertificateValidationException() ||
      AtIOException() ||
      BlockedConnectionException() ||
      AtConnectException() =>
        'offline',
      AtTimeoutException() || TimeoutException() => 'timeout',
      SetupLockTimeoutException() ||
      IndexedDbException() ||
      AtServerAtKeysWriteException() =>
        'storage_failed',
      AtEnrollmentPendingException() => 'onboarding_incomplete',
      PasskeyOnboardingIncompleteException() ||
      MissingAtKeysDocumentException() =>
        'onboarding_incomplete',
      EnrollmentConveyanceException() => 'enrollment_conveyance_failed',
      EnrollmentInFlightException() => 'enrollment_in_flight',
      AtEnrollmentException() ||
      AtInvalidEnrollmentException() =>
        'enrollment_denied',
      SessionClosedException() || StoppedException() => 'closed',
      UnsupportedKeyMaterialException() ||
      UnsupportedOperationException() ||
      UnsupportedError() ||
      ManageAccessRequiredException() ||
      PrfUnavailableException() ||
      UnsupportedPasskeyRecordException() =>
        'unsupported',
      AlreadyOpenException() || AtStorageInUseException() => 'already_open',
      InvalidKeyException() ||
      InvalidAtSignException() ||
      AtKeysUnusableException() ||
      AtKeysValidationException() ||
      AtKeysParseException() ||
      AtKeysFormatException() ||
      AtKeysSourceAbsentException() ||
      AtKeysFileOverwriteException() ||
      AtKeyException() ||
      InvalidAtKeyException() ||
      AtKeyNotFoundException() ||
      KeyNotFoundException() ||
      AtSigningException() ||
      AtSigningVerificationException() ||
      AtEncryptionException() ||
      AtDecryptionException() ||
      PasskeyLostException() ||
      PasskeyRecordAuthenticationException() ||
      PublicKeyMismatchException() ||
      PasskeyCeremonyException() ||
      AtAuthenticationException() =>
        'bad_key',
      BufferOverFlowException() => 'invalid_argument',
      // An at_commons exception that means the atServer, or the client on its
      // behalf, refused the request; each atServer error code maps to one of
      // these. Any other type is unnameable here and falls to `internal`, which
      // the inventory test refuses to let a new bridge-reachable type take by
      // accident.
      AtServerException() ||
      AtThrottleLimitExceeded() ||
      InvalidSyntaxException() ||
      InvalidRequestException() ||
      IllegalStateException() ||
      IllegalArgumentException() =>
        'refused',
      AtLookUpException(:final errorCode) => _lookUpCode(errorCode),
      _ => 'internal',
    };

/// The code for an at_lookup failure, from its own error code: the ones that
/// name a transport failure, a timeout or a failed authentication keep their
/// meaning, and any other is the atServer refusing the request.
String _lookUpCode(String errorCode) => switch (errorCode) {
      'AT0004' || 'AT0007' || 'AT0021' => 'offline',
      'AT0023' => 'timeout',
      'AT0401' => 'pkam_refused',
      'AT0015' || 'AT0016' => 'bad_key',
      _ => 'refused',
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

/// The codes [errorCodeOf] returns that are not `COLLECTION_*` ones: the
/// closed set, sorted. `tool/manifest.dart` publishes it as `errorCodes` in
/// `bridge-manifest.json`.
const atErrorCodes = <String>[
  'already_open',
  'bad_key',
  'closed',
  'enrollment_conveyance_failed',
  'enrollment_denied',
  'enrollment_in_flight',
  'internal',
  'invalid_argument',
  'offline',
  'onboarding_incomplete',
  'pkam_refused',
  'refused',
  'storage_failed',
  'timeout',
  'unsupported',
];

/// Every [collectionErrorCode] value, sorted: the closed set of
/// `COLLECTION_*` codes a [JsCollectionsError] can carry.
/// `tool/manifest.dart` publishes it as `collectionErrorCodes` in
/// `bridge-manifest.json`.
const collectionErrorCodes = <String>[
  'COLLECTION_FAILED',
  'COLLECTION_INVALID_ARGUMENT',
  'COLLECTION_ITEM_ALREADY_EXISTS',
  'COLLECTION_ITEM_HAS_SUB_ITEMS',
  'COLLECTION_ITEM_NOT_FOUND',
  'COLLECTION_ITEM_NOT_OWNER',
  'COLLECTION_ITEM_TOO_DEEP',
  'COLLECTION_ITEM_UNREADABLE',
  'COLLECTION_ITEM_WRONG_TYPE',
  'COLLECTION_PARTIAL_FAILURE',
  'COLLECTION_TYPE_MISMATCH',
];

/// The message JS sees for [error]: fixed here, or built from the exception's
/// fields, each echoed field bounded to one line. A message names a parameter
/// and never its value.
String atErrorMessage(Object error) => switch (error) {
      InvalidArgumentException() => _argumentMessage(error),
      QueueLimitException() =>
        'too many opens are already waiting for this atSign',
      JsCollectionsError() => _collectionMessage(error),
      AtOpenRefusedException(:final state) =>
        'the atServer refused the session (${state.cause?.name ?? 'refused'})',
      AtCredentialRefusedException(:final state) =>
        'the atServer refused the credential (${state.cause?.name ?? 'refused'})',
      PortalSessionOfflineException(:final state) =>
        'the session could not reach the atServer (${state.cause?.name ?? 'offline'})',
      AtEnrollmentPendingException() =>
        'onboarding is incomplete: no usable credential',
      PasskeyOnboardingIncompleteException() ||
      MissingAtKeysDocumentException() =>
        'onboarding is incomplete: log in with the passkey to finish it',
      EnrollmentConveyanceException(:final keyPackageStatus) =>
        'enrollment approved on server, but key conveyance failed (${keyPackageStatus.name})',
      EnrollmentInFlightException() => enrollmentInFlightMessage,
      AtEnrollmentException() ||
      AtInvalidEnrollmentException() =>
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
      PrfUnavailableException() =>
        'passkey PRF is not available in this browser',
      UnsupportedPasskeyRecordException() =>
        'the stored passkey record is not supported',
      InvalidKeyException() => _keyMessage(error),
      AtKeysUnusableException() ||
      AtKeysValidationException() ||
      AtKeysParseException() ||
      AtKeysFormatException() ||
      AtKeysSourceAbsentException() ||
      AtKeysFileOverwriteException() =>
        'the keys cannot be used',
      AtKeyException() ||
      InvalidAtKeyException() ||
      AtKeyNotFoundException() ||
      KeyNotFoundException() =>
        'the key was refused',
      AtSigningException() ||
      AtSigningVerificationException() =>
        'the key material cannot sign or be verified',
      AtEncryptionException() ||
      AtDecryptionException() =>
        'the key material cannot encrypt or decrypt',
      PasskeyLostException() => 'the passkey could not open the atSign',
      PasskeyRecordAuthenticationException() =>
        'the passkey record could not be authenticated',
      PublicKeyMismatchException() =>
        'the keys do not match the published public keys',
      PasskeyCeremonyException() =>
        'the passkey ceremony did not produce a credential',
      AtAuthenticationException() => 'authentication failed',
      InvalidAtSignException() => 'atSign is not valid',
      UnAuthenticatedException() ||
      PkamRefusedException() =>
        'the atServer refused the session',
      UnAuthorizedException() => 'the atServer refused the request',
      SecondaryConnectException() ||
      AtConnectException() ||
      AtIOException() ||
      AtCertificateValidationException() =>
        'the atServer could not be reached',
      BlockedConnectionException() => 'the atServer blocked the connection',
      AtTimeoutException() ||
      TimeoutException() =>
        'the atServer did not answer in time',
      SetupLockTimeoutException() => 'the setup lock could not be acquired',
      IndexedDbException(:final browserError) => browserError == null
          ? 'the browser storage failed'
          : 'the browser storage failed ($browserError)',
      AtServerAtKeysWriteException() =>
        'the passkey key store is not available',
      AtServerException() ||
      AtThrottleLimitExceeded() ||
      InvalidSyntaxException() ||
      InvalidRequestException() ||
      IllegalStateException() ||
      IllegalArgumentException() =>
        'the atServer or the client refused the request',
      BufferOverFlowException() =>
        'the value is larger than the notification limit',
      AlreadyOpenException() || AtStorageInUseException() => alreadyOpenMessage,
      AtLookUpException() => 'the atServer refused the request',
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
