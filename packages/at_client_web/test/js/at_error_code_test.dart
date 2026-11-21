import 'package:at_client/at_client.dart';
import 'package:at_client_web/at_client_web.dart';
import 'package:at_client_web/src/collections/js_collections_adapter.dart';
import 'package:at_client_web/src/js/at_error_code.dart';
import 'package:at_client_web/src/js/js_session.dart';
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
    'JsCollectionsError carries its own code': (
      JsCollectionsError(
          CollectionErrorCodes.notFound, 'item abc is not in the collection'),
      'COLLECTION_ITEM_NOT_FOUND'
    ),
    'JsCollectionsError partial failure': (
      JsCollectionsError(CollectionErrorCodes.partialFailure, 'x'),
      'COLLECTION_PARTIAL_FAILURE'
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
      'enrollment_denied',
      'closed',
      'unsupported',
      'internal',
    };
    final produced = cases.values.map((c) => c.$2).toSet();
    expect(produced.containsAll(mapped), isTrue,
        reason: '${mapped.difference(produced)}');
    expect(
        produced
            .difference({'bad_key'})
            .where((c) => !c.startsWith('COLLECTION_'))
            .toSet(),
        mapped);
  });
}
