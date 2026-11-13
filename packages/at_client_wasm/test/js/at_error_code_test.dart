import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_client_wasm/src/js/at_error_code.dart';
import 'package:at_client_wasm/src/js/js_session.dart';
import 'package:at_client_wasm/src/keys/passkey_port.dart';
import 'package:at_client_wasm/src/keys/passkey_record.dart';
import 'package:at_client_wasm/src/keys/prf_support.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:at_client_wasm/src/session/setup_lock.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

class _Pending extends Fake implements PendingOnboarding {}

void main() {
  final cases = <String, (Object, String)>{
    'PasskeyLostException with a hint': (
      PasskeyLostException('@alice', 'PKAM refused'),
      'passkey_lost'
    ),
    'PasskeyLostException with no hint and no pointer': (
      PasskeyLostException('@alice', 'no enrollment pointer',
          noPasskeyHere: true),
      'no_passkey_here'
    ),
    'PasskeyCeremonyException': (
      PasskeyCeremonyException('cancelled'),
      'passkey_lost'
    ),
    'PasskeyRecordAuthenticationException': (
      PasskeyRecordAuthenticationException(),
      'passkey_lost'
    ),
    'PrfUnavailableException': (
      PrfUnavailableException('no prf'),
      'prf_unavailable'
    ),
    'PkamRefusedException': (PkamRefusedException('eid'), 'pkam_refused'),
    'AtOpenRefusedException': (
      AtOpenRefusedException(
          '@alice', AtConnectionState.refused(AtConnectionCause.revoked)),
      'pkam_refused'
    ),
    'PublicKeyMismatchException': (
      PublicKeyMismatchException(),
      'public_key_mismatch'
    ),
    'SetupLockTimeoutException': (
      const SetupLockTimeoutException('lock'),
      'setup_lock_timeout'
    ),
    'PortalSessionOfflineException': (
      PortalSessionOfflineException(
          '@alice', AtConnectionState.offline(AtConnectionCause.unreachable)),
      'offline'
    ),
    'OnboardingIncompleteException': (
      OnboardingIncompleteException(_Pending(), StateError('x')),
      'onboarding_incomplete'
    ),
    'ActivationUnfinishedException': (
      ActivationUnfinishedException('eid', atKeys: {}, cause: StateError('x')),
      'onboarding_incomplete'
    ),
    'MissingAtKeysDocumentException': (
      MissingAtKeysDocumentException('eid'),
      'onboarding_incomplete'
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
    'UnsupportedPasskeyRecordException': (
      UnsupportedPasskeyRecordException('v9'),
      'unsupported'
    ),
    'UnsupportedError': (UnsupportedError('no locks'), 'unsupported'),
    'ManageAccessException': (ManageAccessException(), 'unsupported'),
    'BadKeyException': (BadKeyException('sharedWith'), 'bad_key'),
    'an unknown Exception': (Exception('x'), 'internal'),
    'an unknown Error': (StateError('x'), 'internal'),
    'a non-exception value': ('text', 'internal'),
  };

  for (final MapEntry(key: name, value: (error, code)) in cases.entries) {
    test('$name maps to $code', () => expect(atErrorCode(error), code));
  }

  test('every W8 code but the bridge-only ones is produced by some mapping',
      () {
    const w8 = {
      'no_passkey_here',
      'passkey_lost',
      'prf_unavailable',
      'pkam_refused',
      'public_key_mismatch',
      'setup_lock_timeout',
      'offline',
      'onboarding_incomplete',
      'enrollment_denied',
      'closed',
      'unsupported',
      'internal',
    };
    final produced = cases.values.map((c) => c.$2).toSet();
    expect(produced.containsAll(w8), isTrue,
        reason: '${w8.difference(produced)}');
    expect(w8.containsAll(produced.difference({'bad_key'})), isTrue);
  });
}
