import 'package:at_client/at_client.dart';

import '../exceptions.dart';

// The one place an exception becomes an error code and a message for JS.
// Both are pure functions of the thrown type: no exception's own text ever
// chooses a code, and no text reaches JS unless this file lets it.

/// What a closed session and a stopped client both reject with.
const _closedMessage = 'the session is closed';

/// The longest message an `invalid_argument` rejection carries.
const _maxMessageLength = 128;

final _controlChars =
    RegExp(r'[\x00-\x1f\x7f-\x9f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]');

/// The `AtError.code` for [error]: one string per typed exception the
/// session layer throws, a `COLLECTION_*` code for a collection failure, and
/// `internal` for anything else.
String atErrorCode(Object error) => switch (error) {
      InvalidArgumentException() => 'invalid_argument',
      CollectionException(:final kind) => collectionErrorCode(kind),
      AtOpenRefusedException() => 'pkam_refused',
      PortalSessionOfflineException() => 'offline',
      AtEnrollmentPendingException() => 'onboarding_incomplete',
      EnrollmentConveyanceException() => 'enrollment_conveyance_failed',
      EnrollmentInFlightException() => 'enrollment_in_flight',
      AtEnrollmentException() => 'enrollment_denied',
      SessionClosedException() || StoppedException() => 'closed',
      UnsupportedKeyMaterialException() ||
      UnsupportedError() ||
      ManageAccessException() =>
        'unsupported',
      BadKeyException() ||
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

/// The message JS sees for [error]. A collection failure carries the
/// bounded detail the adapter wrote; every other message is fixed here, or
/// names a parameter and never its value.
String atErrorMessage(Object error) => switch (error) {
      InvalidArgumentException(:final message) => _bounded(message),
      CollectionException(:final message) => message,
      AtOpenRefusedException(:final state) =>
        'the atServer refused the session (${state.cause?.name ?? 'refused'})',
      PortalSessionOfflineException(:final state) =>
        'the session could not reach the atServer (${state.cause?.name ?? 'offline'})',
      AtEnrollmentPendingException() =>
        'onboarding is incomplete: no usable credential',
      EnrollmentConveyanceException(:final keyPackageStatus) =>
        'enrollment approved on server, but key conveyance failed (${keyPackageStatus.name})',
      EnrollmentInFlightException() =>
        'a decision for this request is already in flight',
      AtEnrollmentException() =>
        'the enrollment request was denied or is not pending',
      SessionClosedException() || StoppedException() => _closedMessage,
      UnsupportedKeyMaterialException() =>
        'the keys carry unsupported cryptographic material',
      ManageAccessException() => 'this session cannot manage enrollments',
      UnsupportedError(:final message) =>
        _oneLine(message ?? 'unsupported operation'),
      BadKeyException(:final reason) => reason,
      AtNoCredentialException() => 'keys hold no usable credential',
      InvalidAtSignException() => 'atSign is not valid',
      _ => 'internal error',
    };

String _oneLine(String value) => value.replaceAll(_controlChars, ' ');

String _bounded(String value) {
  final line = _oneLine(value);
  return line.length <= _maxMessageLength
      ? line
      : line.substring(0, _maxMessageLength);
}
