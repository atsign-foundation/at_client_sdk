import 'package:at_auth/at_auth.dart' show AtEnrollmentResponse;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_client_wasm/src/collections/js_collections_adapter.dart';
import 'package:at_client_wasm/src/js/at_error_code.dart';
import 'package:at_client_wasm/src/js/js_session.dart';
import 'package:test/test.dart';

void main() {
  final cases = <String, (Object, String)>{
    'AtOpenRefusedException': (
      AtOpenRefusedException(
          '@alice', AtConnectionState.refused(AtConnectionCause.revoked)),
      'pkam_refused'
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
    'SessionClosedException': (SessionClosedException(), 'closed'),
    'UnsupportedKeyMaterialException': (
      UnsupportedKeyMaterialException('@alice'),
      'unsupported'
    ),
    'UnsupportedError': (UnsupportedError('no locks'), 'unsupported'),
    'ManageAccessException': (ManageAccessException(), 'unsupported'),
    'BadKeyException': (BadKeyException('sharedWith'), 'bad_key'),
    'AtNoCredentialException': (AtNoCredentialException('@alice'), 'bad_key'),
    'InvalidAtSignException': (InvalidAtSignException('bad'), 'bad_key'),
    'JsCollectionsError carries its own code': (
      JsCollectionsError(
          CollectionErrorCodes.notFound, 'item abc is not in the collection'),
      'COLLECTION_ITEM_NOT_FOUND'
    ),
    'JsCollectionsError partial failure': (
      JsCollectionsError(CollectionErrorCodes.partialFailure, 'x'),
      'COLLECTION_PARTIAL_FAILURE'
    ),
    'JsCollectionsError invalid argument': (
      JsCollectionsError(CollectionErrorCodes.invalidArgument, 'bad'),
      'COLLECTION_INVALID_ARGUMENT'
    ),
    'JsCollectionsError not owner': (
      JsCollectionsError(CollectionErrorCodes.notOwner, 'other'),
      'COLLECTION_ITEM_NOT_OWNER'
    ),
    'JsCollectionsError already exists': (
      JsCollectionsError(CollectionErrorCodes.alreadyExists, 'exists'),
      'COLLECTION_ITEM_ALREADY_EXISTS'
    ),
    'JsCollectionsError has sub items': (
      JsCollectionsError(CollectionErrorCodes.hasSubItems, 'subs'),
      'COLLECTION_ITEM_HAS_SUB_ITEMS'
    ),
    'JsCollectionsError unreadable': (
      JsCollectionsError(CollectionErrorCodes.unreadable, 'unreadable'),
      'COLLECTION_ITEM_UNREADABLE'
    ),
    'JsCollectionsError type mismatch': (
      JsCollectionsError(CollectionErrorCodes.typeMismatch, 'mismatch'),
      'COLLECTION_TYPE_MISMATCH'
    ),
    'JsCollectionsError wrong type': (
      JsCollectionsError(CollectionErrorCodes.wrongType, 'wrong'),
      'COLLECTION_ITEM_WRONG_TYPE'
    ),
    'JsCollectionsError failed': (
      JsCollectionsError(CollectionErrorCodes.failed, 'failed'),
      'COLLECTION_FAILED'
    ),
    'JsCollectionsError too deep': (
      JsCollectionsError(CollectionErrorCodes.tooDeep, 'deep'),
      'COLLECTION_ITEM_TOO_DEEP'
    ),
    'an unknown Exception': (Exception('x'), 'internal'),
    'an unknown Error': (StateError('x'), 'internal'),
    'a non-exception value': ('text', 'internal'),
  };

  for (final MapEntry(key: name, value: (error, code)) in cases.entries) {
    test('$name maps to $code', () => expect(atErrorCode(error), code));
  }

  test('every code the facade maps to is produced by some mapping', () {
    const mapped = {
      'pkam_refused',
      'offline',
      'onboarding_incomplete',
      'enrollment_conveyance_failed',
      'enrollment_denied',
      'closed',
      'unsupported',
      'bad_key',
      'internal',
    };
    final produced = cases.values.map((c) => c.$2).toSet();
    expect(produced.containsAll(mapped), isTrue,
        reason: '${mapped.difference(produced)}');
    expect(produced.where((c) => !c.startsWith('COLLECTION_')).toSet(), mapped);
  });
}
