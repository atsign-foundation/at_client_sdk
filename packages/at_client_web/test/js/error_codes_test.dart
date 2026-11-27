import 'dart:async';

import 'package:at_auth/at_auth.dart' show AtEnrollmentResponse;
import 'package:at_auth/passkey.dart'
    show
        PasskeyCeremonyException,
        PrfUnavailableException,
        UnsupportedPasskeyRecordException;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
import 'package:at_client/passkey.dart'
    show
        AtServerAtKeysLockedException,
        AtServerAtKeysWriteException,
        MissingAtKeysDocumentException,
        PasskeyLostException,
        PasskeyOnboardingIncompleteException,
        PkamRefusedException,
        PublicKeyMismatchException;
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/error_codes.dart';
import 'package:test/test.dart';

void main() {
  final cases = <String, (Object, String)>{
    'AtOpenRefusedException': (
      AtOpenRefusedException(
          '@alice', AtConnectionState.refused(AtConnectionCause.revoked)),
      'pkam_refused'
    ),
    'AtOpenRefusedException (no atServer)': (
      AtOpenRefusedException(
          '@alice', AtConnectionState.offline(AtConnectionCause.noAtServer)),
      'offline'
    ),
    'PortalSessionOfflineException': (
      PortalSessionOfflineException(
          '@alice', AtConnectionState.offline(AtConnectionCause.unreachable)),
      'offline'
    ),
    'AtEnrollmentPendingException': (
      AtEnrollmentPendingException('@alice', ['eid']),
      'onboarding_incomplete'
    ),
    'EnrollmentConveyanceException': (
      EnrollmentConveyanceException('conveyance refused',
          response: AtEnrollmentResponse('eid', EnrollmentStatus.approved),
          keyPackageStatus: KeyPackageStatus.rejected),
      'enrollment_conveyance_failed'
    ),
    'AtEnrollmentException (denied)': (
      AtEnrollmentException('The enrollment: eid is denied'),
      'enrollment_denied'
    ),
    'StoppedException': (StoppedException('wait cancelled'), 'closed'),
    'StoppedException (the session is closed)': (
      StoppedException('the session is closed'),
      'closed'
    ),
    'InvalidArgumentException': (
      InvalidArgumentException('opts', expected: 'an object'),
      'invalid_argument'
    ),
    'EnrollmentInFlightException': (
      EnrollmentInFlightException(),
      'enrollment_in_flight'
    ),
    'UnsupportedKeyMaterialException': (
      UnsupportedKeyMaterialException('@alice'),
      'unsupported'
    ),
    'UnsupportedOperationException': (
      UnsupportedOperationException(UnsupportedOperation.secureContext),
      'unsupported'
    ),
    'UnsupportedError': (UnsupportedError('no locks'), 'unsupported'),
    'ManageAccessRequiredException': (
      ManageAccessRequiredException(),
      'unsupported'
    ),
    'InvalidKeyException': (
      InvalidKeyException(KeyRefusal.sharedWithMissing),
      'bad_key'
    ),
    'AtNoCredentialException': (AtNoCredentialException('@alice'), 'bad_key'),
    'InvalidAtSignException': (InvalidAtSignException('bad'), 'bad_key'),
    'NotifyFailedException send failed': (
      NotifyFailedException(NotifyFailure.sendFailed),
      'notify_failed'
    ),
    'NotifyFailedException offline': (
      NotifyFailedException(NotifyFailure.offline),
      'offline'
    ),
    'NotifyFailedException timeout': (
      NotifyFailedException(NotifyFailure.timeout),
      'timeout'
    ),
    'JsCollectionsError carries its own code': (
      JsCollectionsError(CollectionFailure.notFound),
      'COLLECTION_ITEM_NOT_FOUND'
    ),
    'JsCollectionsError partial failure': (
      JsCollectionsError(CollectionFailure.partialFailure),
      'COLLECTION_PARTIAL_FAILURE'
    ),
    'JsCollectionsError invalid argument': (
      JsCollectionsError(CollectionFailure.invalidArgument),
      'COLLECTION_INVALID_ARGUMENT'
    ),
    'JsCollectionsError not owner': (
      JsCollectionsError(CollectionFailure.notOwner),
      'COLLECTION_ITEM_NOT_OWNER'
    ),
    'JsCollectionsError already exists': (
      JsCollectionsError(CollectionFailure.alreadyExists),
      'COLLECTION_ITEM_ALREADY_EXISTS'
    ),
    'JsCollectionsError has sub items': (
      JsCollectionsError(CollectionFailure.hasSubItems),
      'COLLECTION_ITEM_HAS_SUB_ITEMS'
    ),
    'JsCollectionsError unreadable': (
      JsCollectionsError(CollectionFailure.unreadable),
      'COLLECTION_ITEM_UNREADABLE'
    ),
    'JsCollectionsError type mismatch': (
      JsCollectionsError(CollectionFailure.typeMismatch),
      'COLLECTION_TYPE_MISMATCH'
    ),
    'JsCollectionsError wrong type': (
      JsCollectionsError(CollectionFailure.wrongType),
      'COLLECTION_ITEM_WRONG_TYPE'
    ),
    'JsCollectionsError failed': (
      JsCollectionsError(CollectionFailure.failed),
      'COLLECTION_FAILED'
    ),
    'JsCollectionsError too deep': (
      JsCollectionsError(CollectionFailure.tooDeep),
      'COLLECTION_ITEM_TOO_DEEP'
    ),
    'PasskeyLostException': (
      PasskeyLostException('@alice', 'no passkey matched'),
      'passkey_lost'
    ),
    'PasskeyLostException caused by a PKAM refusal': (
      PasskeyLostException('@alice', 'refused',
          cause: PkamRefusedException('eid-1')),
      'pkam_refused'
    ),
    'PkamRefusedException': (PkamRefusedException('eid-1'), 'pkam_refused'),
    'an unknown Exception': (Exception('x'), 'internal'),
    'an unknown Error': (StateError('x'), 'internal'),
    'a non-exception value': ('text', 'internal'),
  };

  for (final MapEntry(key: name, value: (error, code)) in cases.entries) {
    test('$name maps to $code', () => expect(errorCodeOf(error), code));
  }

  test('an atSign with no atServer rejects offline, not pkam_refused', () {
    final noAtServer = AtOpenRefusedException(
        '@alice', AtConnectionState.offline(AtConnectionCause.noAtServer));
    expect(errorCodeOf(noAtServer), 'offline');
    expect(atErrorMessage(noAtServer), 'no atServer was found for this atSign');
    expect(atErrorMessage(noAtServer), isNot(contains('@alice')));

    for (final cause in AtConnectionCause.values
        .where((cause) => cause != AtConnectionCause.noAtServer)) {
      final refused =
          AtOpenRefusedException('@alice', AtConnectionState.refused(cause));
      expect(errorCodeOf(refused), 'pkam_refused', reason: cause.name);
      expect(atErrorMessage(refused),
          'the atServer refused the session (${cause.name})',
          reason: cause.name);
    }
  });

  test('every code the bridge can reject with is produced by one mapping', () {
    const mapped = {
      'pkam_refused',
      'offline',
      'timeout',
      'onboarding_incomplete',
      'enrollment_conveyance_failed',
      'enrollment_denied',
      'invalid_argument',
      'enrollment_in_flight',
      'closed',
      'unsupported',
      'bad_key',
      'notify_failed',
      'passkey_lost',
      'internal',
    };
    final produced = cases.values.map((c) => c.$2).toSet();
    expect(produced.containsAll(mapped), isTrue,
        reason: '${mapped.difference(produced)}');
    final sessionCodes =
        produced.where((c) => !c.startsWith('COLLECTION_')).toSet();
    expect(sessionCodes, mapped);
    expect(atErrorCodes.toSet(), sessionCodes);
    final collection = {
      for (final kind in CollectionFailure.values) collectionErrorCode(kind)
    };
    expect(collection, hasLength(11));
    expect(collectionErrorCodes.toSet(), collection);
    expect(
        produced.where((c) => c.startsWith('COLLECTION_')).toSet(), collection);
  });

  test(
      'a passkey prompt that failed, was cancelled or found no passkey rejects passkey_lost',
      () {
    const message =
        'the passkey sign-in did not complete; try again or reset this browser';
    for (final error in [
      PasskeyLostException('@alice', 'the prompt failed',
          cause: PasskeyCeremonyException('cancelled')),
      PasskeyLostException('@alice', 'the prompt timed out',
          cause: PasskeyCeremonyException('timed out')),
      PasskeyLostException('@alice', 'no passkey matched'),
      PasskeyLostException('@alice', 'the record did not open',
          cause: FormatException('bad record')),
    ]) {
      expect(errorCodeOf(error), 'passkey_lost');
      expect(atErrorMessage(error), message);
    }
  });

  test(
      'a passkey enrollment the atServer refused rejects pkam_refused, chosen by the cause type',
      () {
    final error = PasskeyLostException('@alice', 'the atServer refused PKAM',
        cause: PkamRefusedException('e-1'));
    expect(errorCodeOf(error), 'pkam_refused');
    expect(
        atErrorMessage(error), 'the atServer refused this passkey enrollment');
    expect(atErrorMessage(error), isNot(contains('e-1')));
    expect(atErrorMessage(error), isNot(contains('@alice')));
  });

  test('a passkey code is chosen by the cause type, never by the reason text',
      () {
    for (final reason in [
      'PKAM refused',
      'pkam_refused',
      'unsupported',
      'the atServer refused this passkey enrollment',
    ]) {
      final error = PasskeyLostException('@alice', reason);
      expect(errorCodeOf(error), 'passkey_lost', reason: reason);
      expect(
          atErrorMessage(error),
          'the passkey sign-in did not complete; '
          'try again or reset this browser');
    }
    final caused = PasskeyLostException('@alice', 'PKAM refused',
        cause: PasskeyCeremonyException('PKAM refused'));
    expect(errorCodeOf(caused), 'passkey_lost');
  });

  test('a browser or authenticator without passkey PRF rejects unsupported',
      () {
    final error = PrfUnavailableException(
        'This platform or authenticator does not support passkey PRF.');
    expect(errorCodeOf(error), 'unsupported');
    expect(atErrorMessage(error),
        'this browser or authenticator has no passkey PRF');
  });

  test('a setup lock held by another tab rejects timeout', () {
    final error = SetupLockTimeoutException('setup-@alice');
    expect(errorCodeOf(error), 'timeout');
    expect(atErrorMessage(error), 'another tab is setting up this atSign');
  });

  test(
      'key mismatch, a missing atKeys document and passkey storage failures stay internal',
      () {
    final errors = <Object>[
      PublicKeyMismatchException(),
      MissingAtKeysDocumentException('eid-1'),
      IndexedDbException('QuotaExceededError'),
      UnsupportedPasskeyRecordException('record version 9'),
      AtServerAtKeysWriteException('the write was refused'),
      AtServerAtKeysLockedException('the lock was lost'),
      PasskeyOnboardingIncompleteException(Atsign('@alice'),
          cause: Exception('stopped')),
    ];
    expect(errors, hasLength(7));
    for (final error in errors) {
      expect(errorCodeOf(error), 'internal', reason: '${error.runtimeType}');
      expect(atErrorMessage(error), 'internal error',
          reason: '${error.runtimeType}');
    }
  });

  test(
      'a direct PKAM refusal on the passkey path rejects pkam_refused with a fixed message',
      () {
    final error = PkamRefusedException('e-123');
    expect(errorCodeOf(error), 'pkam_refused');
    expect(
        atErrorMessage(error), 'the atServer refused this passkey enrollment');
    expect(atErrorMessage(error), isNot(contains('e-123')));
  });

  test(
      'a passkey failure message names no atSign, lock, reason, enrollment id or browser error',
      () {
    const fixed = {
      'the atServer refused this passkey enrollment',
      'the passkey sign-in did not complete; try again or reset this browser',
      'this browser or authenticator has no passkey PRF',
      'another tab is setting up this atSign',
      'internal error',
    };
    final tail = '${'x\u202e' * 400}\n${'y' * 1000000}';
    final atSign = '@sentinel-atSign$tail';
    final reason = 'sentinel-reason$tail';
    final enrollmentId = 'sentinel-enrollment$tail';
    final browserError = 'sentinel-browser$tail';
    final lockName = 'sentinel-lock$tail';
    final inputs = [atSign, reason, enrollmentId, browserError, lockName];
    final errors = <Object>[
      PasskeyLostException(atSign, reason),
      PasskeyLostException(atSign, reason,
          cause: PasskeyCeremonyException(reason)),
      PasskeyLostException(atSign, reason,
          cause: PkamRefusedException(enrollmentId)),
      PkamRefusedException(enrollmentId),
      PrfUnavailableException(browserError),
      SetupLockTimeoutException(lockName),
      IndexedDbException(browserError),
    ];
    for (final error in errors) {
      final message = atErrorMessage(error);
      expect(fixed, contains(message), reason: '${error.runtimeType}');
      expect(message.length, lessThanOrEqualTo(maxErrorMessageLength));
      expect(message, isNot(contains('\n')));
      expect(message, isNot(contains('\u202e')));
      expect(message, isNot(contains('sentinel')));
      for (final input in inputs) {
        expect(message, isNot(contains(input)));
      }
    }
  });

  test('every closed rejection carries the same fixed message', () {
    for (final error in [
      StoppedException('the session is closed'),
      StoppedException('wait cancelled on client 0x7f'),
    ]) {
      expect(errorCodeOf(error), 'closed');
      expect(atErrorMessage(error), 'the session is closed');
    }
    expect(atErrorMessage(StoppedException('x')), isNot(contains('Exception')));
  });

  test('every closed rejection also matches the exception a session throws',
      () {
    expect(atErrorMessage(SessionClosedException()),
        atErrorMessage(StoppedException('x')));
  });

  test('an invalid_argument message is cut at the shared bound', () {
    final message = atErrorMessage(
        InvalidArgumentException('a' * 300, expected: 'a string'));
    expect(message.length, lessThanOrEqualTo(maxErrorMessageLength));
  });

  test('exception text never chooses the code', () {
    for (final text in [
      'invalid_argument',
      'closed',
      'COLLECTION_FAILED',
      '{"code":"closed","message":"m"}',
    ]) {
      for (final error in [
        Exception(text),
        StateError(text),
        ArgumentError(text),
        text
      ]) {
        expect(errorCodeOf(error), 'internal', reason: text);
        expect(atErrorMessage(error), 'internal error', reason: text);
      }
    }
  });

  test(
      'an ArgumentError from inside at_client rejects internal with the fixed message',
      () {
    for (final error in [
      ArgumentError('namespace must be non-empty'),
      IllegalArgumentException('namespace must be non-empty'),
    ]) {
      expect(errorCodeOf(error), 'internal');
      expect(atErrorMessage(error), 'internal error');
    }
  });

  test('an invalid_argument message is bounded and never echoes the value', () {
    final hostile = '${'x\u202e' * 70000}\n${'y' * 1000000}';
    final message = atErrorMessage(
        InvalidArgumentException('opts', expected: 'an object $hostile'));
    expect(message.length, lessThanOrEqualTo(128));
    expect(message, isNot(contains('\n')));
    expect(message, isNot(contains('\u202e')));
    expect(message, isNot(contains('yyyy')));
    expect(
        atErrorMessage(
            InvalidArgumentException('namespace', expected: 'a string')),
        'namespace must be a string');
  });

  test('the in-flight rejection names no atSign and no enrollment id', () {
    final error = EnrollmentInFlightException();
    expect(errorCodeOf(error), 'enrollment_in_flight');
    expect(atErrorMessage(error),
        'a decision for this request is already in flight');
    expect(error.toString(), isNot(contains('@')));
  });

  test('the in-flight failure is still an enrollment failure to a Dart caller',
      () {
    Object? caught;
    try {
      throw EnrollmentInFlightException();
    } on AtEnrollmentException catch (e) {
      caught = e;
    }
    expect(caught, isA<EnrollmentInFlightException>());
    expect(errorCodeOf(caught), 'enrollment_in_flight');
  });

  test('The error codes are the COLLECTION_ and COLLECTION_ITEM_ names', () {
    const expected = {
      CollectionFailure.invalidArgument: 'COLLECTION_INVALID_ARGUMENT',
      CollectionFailure.partialFailure: 'COLLECTION_PARTIAL_FAILURE',
      CollectionFailure.typeMismatch: 'COLLECTION_TYPE_MISMATCH',
      CollectionFailure.failed: 'COLLECTION_FAILED',
      CollectionFailure.notFound: 'COLLECTION_ITEM_NOT_FOUND',
      CollectionFailure.notOwner: 'COLLECTION_ITEM_NOT_OWNER',
      CollectionFailure.alreadyExists: 'COLLECTION_ITEM_ALREADY_EXISTS',
      CollectionFailure.unreadable: 'COLLECTION_ITEM_UNREADABLE',
      CollectionFailure.hasSubItems: 'COLLECTION_ITEM_HAS_SUB_ITEMS',
      CollectionFailure.wrongType: 'COLLECTION_ITEM_WRONG_TYPE',
      CollectionFailure.tooDeep: 'COLLECTION_ITEM_TOO_DEEP',
    };
    expect(expected.keys.toSet(), CollectionFailure.values.toSet());
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(errorCodeOf(JsCollectionsError(key)), value);
      expect(collectionErrorCode(key), value);
    }
    expect(expected.values.toSet(), hasLength(11));
  });

  group('the bridge authors every message JS sees', () {
    String text(Object e) => atErrorMessage(e);

    test('a session argument error names its parameter from the fields', () {
      expect(text(InvalidArgumentException('regex')),
          'regex must be a valid regular expression');
      expect(
          text(InvalidArgumentException('owner', expected: 'a valid atSign')),
          'owner must be a valid atSign');
      expect(text(InvalidArgumentException.missing('opts')),
          'opts must not be null');
    });

    test('a key refusal is worded from its enum, never from exception text',
        () {
      for (final refusal in KeyRefusal.values) {
        final message = text(InvalidKeyException(refusal));
        expect(message, isNotEmpty, reason: refusal.name);
        expect(message.length, lessThanOrEqualTo(maxErrorMessageLength));
      }
      expect(text(InvalidKeyException(KeyRefusal.sharedWithMissing)),
          'notify needs sharedWith');
      expect(text(InvalidKeyException(KeyRefusal.keysJson)),
          'keys is not valid JSON');
      expect(
          text(InvalidKeyException.field(
              InvalidArgumentException('key', expected: 'a string'))),
          'key must be a string');
    });

    test('a notify failure is worded from its kind, never from at_client text',
        () {
      const expected = {
        NotifyFailure.sendFailed: (
          'notify_failed',
          'sending the notification failed'
        ),
        NotifyFailure.offline: ('offline', 'the atServer could not be reached'),
        NotifyFailure.timeout: (
          'timeout',
          'the atServer did not answer in time'
        ),
      };
      expect(expected.keys.toSet(), NotifyFailure.values.toSet());
      for (final MapEntry(key: kind, value: (code, message))
          in expected.entries) {
        final error = NotifyFailedException(kind);
        expect(errorCodeOf(error), code, reason: kind.name);
        expect(atErrorMessage(error), message, reason: kind.name);
      }
    });

    test('a transport failure outside notify keeps the code and message it had',
        () {
      for (final error in [
        AtConnectException('x'),
        SecondaryConnectException('x'),
        AtIOException('x'),
        UnAuthorizedException('x'),
        AtTimeoutException('x'),
        TimeoutException('x'),
      ]) {
        expect(errorCodeOf(error), 'internal', reason: '${error.runtimeType}');
        expect(atErrorMessage(error), 'internal error',
            reason: '${error.runtimeType}');
      }
    });

    test('an unsupported operation is worded by the bridge, not by its error',
        () {
      for (final error in [
        UnsupportedError('x' * 5000),
        UnsupportedError('line\nbreak sentinel-7\u202e'),
        UnsupportedError('a secure context (HTTPS) is required'),
      ]) {
        final message = text(error);
        expect(message, 'the operation is not supported here');
        expect(message, isNot(contains('sentinel')));
      }
    });

    test('an unsupported operation raised here keeps its text, from its enum',
        () {
      expect(
          text(UnsupportedOperationException(
              UnsupportedOperation.secureContext)),
          'a secure context (HTTPS) is required');
      for (final operation in UnsupportedOperation.values) {
        expect(errorCodeOf(UnsupportedOperationException(operation)),
            'unsupported');
      }
    });

    test('a collection rejection is worded from its kind and fields alone', () {
      final cases = <JsCollectionsError, String>{
        JsCollectionsError(CollectionFailure.notFound): 'item not found',
        JsCollectionsError(CollectionFailure.alreadyExists):
            'item already exists',
        JsCollectionsError(CollectionFailure.hasSubItems): 'item has sub-items',
        JsCollectionsError(CollectionFailure.failed): 'operation failed',
        JsCollectionsError(CollectionFailure.typeMismatch):
            'a where clause compared values of different types',
        JsCollectionsError(CollectionFailure.tooDeep):
            'item data nests deeper than 64 levels',
        JsCollectionsError(CollectionFailure.partialFailure, failures: const [
          {'op': 'put'},
          {'op': 'put'}
        ]): '2 key-level write(s) failed',
        JsCollectionsError(CollectionFailure.notOwner,
                id: 'A1', owner: '@bob', collectionOwner: '@alice'):
            'item "a1" is owned by @bob, not @alice',
        JsCollectionsError(CollectionFailure.wrongType,
            id: 'a1',
            foundType: 'Note',
            expectedType: 'Todo'): 'item "a1" is a "Note", not a "Todo"',
        JsCollectionsError(CollectionFailure.unreadable, id: 'a1'):
            'item "a1" could not be read',
        JsCollectionsError(CollectionFailure.unreadable,
            id: 'a1',
            owner: '@bob'): 'item "a1" owned by @bob could not be read',
        JsCollectionsError(CollectionFailure.invalidArgument):
            'invalid argument',
        JsCollectionsError(CollectionFailure.invalidArgument,
                refusal: CollectionRefusal.collectionName):
            'collection name must be a valid key name',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.type): 'type must be a non-empty string',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.expiration): 'expirationMs must be > 0',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.eventSource,
            subject: 'x'): 'unknown eventSource "x"',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.wherePath,
            subject: 'a..b'): 'empty segment in where path "a..b"',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.whereOperator,
            subject: '=<'): 'unknown where operator "=<"',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.whereValue,
            subject: '<'): 'where "<" needs a number or string value',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.atSign): 'invalid atSign',
        JsCollectionsError(CollectionFailure.invalidArgument,
            refusal: CollectionRefusal.itemId,
            subject: 'id must not be empty'): 'id must not be empty',
        JsCollectionsError(CollectionFailure.invalidArgument,
                refusal: CollectionRefusal.typeTag):
            'collection is already open with a different type',
      };
      for (final MapEntry(key: error, value: expected) in cases.entries) {
        expect(text(error), expected, reason: error.toString());
      }
      expect(cases.keys.map((error) => error.refusal).toSet(),
          {...CollectionRefusal.values, null},
          reason: 'every refusal, and the unrefused default, needs a case');
    });

    test('a subject the bridge echoes is cut to one bounded line', () {
      final message = text(JsCollectionsError(CollectionFailure.invalidArgument,
          refusal: CollectionRefusal.whereOperator,
          subject: '${'x\u202e' * 500}\n'));
      expect(message.length, lessThanOrEqualTo(maxErrorMessageLength));
      expect(message, isNot(contains('\n')));
      expect(message, isNot(contains('\u202e')));
    });

    test('an item id refusal carries the text AtCollection gave, bounded', () {
      final message = text(JsCollectionsError(CollectionFailure.invalidArgument,
          refusal: CollectionRefusal.itemId, subject: 'id\n${'z' * 400}'));
      expect(message, startsWith('id '));
      expect(message.length, lessThanOrEqualTo(maxErrorMessageLength));
    });

    test('a Dart caller still reads a message on each exception', () {
      expect(InvalidArgumentException('regex').message, contains('regex'));
      expect(
          JsCollectionsError(CollectionFailure.notFound).message, isNotEmpty);
    });
  });
}
