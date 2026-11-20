import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/io/memory_io.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtLookUp extends Mock implements AtLookupImpl {}

class _MockAtEnrollment extends Mock implements AtEnrollment {}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

class _FakeAtLookUp extends Fake implements AtLookupImpl {}

class _FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class _FakeFinder implements SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('abcd', 123);
}

/// Activations of @alice whose PKAM, run once the atServer has accepted the
/// CRAM secret, is stopped or refused.
///
/// Catalogue: features/at_auth/activation_stopped.feature
void main() {
  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    registerFallbackValue(_FakeEnrollmentRequest());
    registerFallbackValue(_FakeAtLookUp());
  });

  late InMemoryAtKeysIo keys;

  setUp(() => keys = InMemoryAtKeysIo());

  Future<void> activate(Never Function() pkam) {
    final lookUp = _MockAtLookUp();
    final enrollment = _MockAtEnrollment();
    when(() => lookUp.secondaryAddressFinder).thenReturn(_FakeFinder());
    when(() => lookUp.executeCommand(any(that: startsWith('lookup:publickey')),
            auth: any(named: 'auth')))
        .thenAnswer((_) async => throw AtLookUpException('AT0015', 'none'));
    var cramAccepted = false;
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async {
      if (!cramAccepted) return cramAccepted = true;
      pkam();
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((_) async => 'data:2');
    when(() => lookUp.dropConnection()).thenAnswer((_) async {});
    when(() => enrollment.submit(any(), lookUp)).thenAnswer(
        (_) async => AtEnrollmentResponse('abc123', EnrollmentStatus.approved));
    final request =
        AtOnboardingRequest('@alice', signingAlgoType: SigningAlgoType.rsa2048)
          ..atKeysIo = keys
          ..appName = 'wavi'
          ..deviceName = 'phone';
    return AtAuthImpl(
        atLookUp: lookUp,
        pkamAuthenticator: PkamAuthenticator(),
        atEnrollment: enrollment,
        clientConfig: const {}).onboard(request, 'cram123');
  }

  void expectNoKeysWritten() => expect(
      () => keys.read('@alice'), throwsA(isA<AtKeysNotInMemoryException>()),
      reason: 'an activation that does not finish writes no keys');

  test(
      'An activation whose connection is stopped while it authenticates by '
      'PKAM throws StoppedException', () async {
    final stopped = StoppedException('the lookup for @alice has been stopped');

    await expectLater(activate(() => throw stopped), throwsA(same(stopped)),
        reason: 'the caller stopped the connection, so the activation says '
            'so, not that the login failed');
    expectNoKeysWritten();
  });

  test(
      'An activation whose PKAM the atServer refuses still throws '
      'AtAuthenticationException', () async {
    await expectLater(
        activate(() => throw AtAuthErrorReplyException(
            'Failed connecting to @alice. '
            'error:AT0027:enrollment_id: abc123 is revoked',
            errorCode: 'AT0027')),
        throwsA(isA<AtAuthenticationException>()),
        reason: 'a refusal is still a failed login');
    expectNoKeysWritten();
  });
}
