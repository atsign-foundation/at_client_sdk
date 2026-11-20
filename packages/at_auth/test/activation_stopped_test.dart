import 'dart:io' show SocketException;

import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/retry_options.dart';
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
      SecondaryAddress('127.0.0.1', 123);
}

Future<String?> _notActivated() async =>
    throw AtLookUpException('AT0015', 'none');

/// Activations of @alice stopped while they wait for the atServer or
/// authenticate by PKAM, or whose PKAM the atServer refuses.
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

  Future<void> activate(Never Function() pkam,
      {Future<String?> Function() publicKeyCheck = _notActivated,
      RetryOptions retryOptions = RetryOptions.defaultRetryOptions}) {
    final lookUp = _MockAtLookUp();
    final enrollment = _MockAtEnrollment();
    when(() => lookUp.secondaryAddressFinder).thenReturn(_FakeFinder());
    when(() => lookUp.executeCommand(any(that: startsWith('lookup:publickey')),
        auth: any(named: 'auth'))).thenAnswer((_) => publicKeyCheck());
    var cramAccepted = false;
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async {
      if (!cramAccepted) return cramAccepted = true;
      pkam();
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((_) async => 'data:2');
    when(() => lookUp.dropConnection()).thenAnswer((_) async {});
    when(() => enrollment.submit(any(), lookUp)).thenAnswer(
        (_) async => AtEnrollmentResponse('abc123', EnrollmentStatus.approved));
    final request = AtOnboardingRequest('@alice',
        signingAlgoType: SigningAlgoType.rsa2048, retryOptions: retryOptions)
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

  test(
      'An activation whose connection is stopped while it waits for its '
      'atServer throws StoppedException', () async {
    final stopped = StoppedException('the lookup for @alice has been stopped');
    var checks = 0;
    Future<String?> stoppedCheck() async {
      checks++;
      throw stopped;
    }

    const waitFor3s = RetryOptions(
        maxRetries: 10,
        retryDelay: Duration(milliseconds: 100),
        overallTimeout: Duration(seconds: 3));

    final thrown = await activate(() => fail('the wait never ended'),
            publicKeyCheck: stoppedCheck, retryOptions: waitFor3s)
        .then<Object?>((_) => null, onError: (Object e) => e);

    expect(checks, 1,
        reason: 'a stop ends the wait, so the atServer is asked once; a retry '
            'would ask again within 100ms of a 3s deadline');
    expect(thrown, same(stopped),
        reason: 'the caller stopped the connection, so the activation says '
            'so, not that its wait timed out');
    expectNoKeysWritten();
  });

  group('Given an activation of @alice whose atServer does not answer', () {
    test(
        'when it waits for its atServer, then it asks again until its '
        'deadline and throws AtTimeoutException', () async {
      var checks = 0;
      Future<String?> unanswered() async {
        checks++;
        throw const SocketException('connection refused');
      }

      const waitFor1s = RetryOptions(
          maxRetries: 10,
          retryDelay: Duration(milliseconds: 100),
          overallTimeout: Duration(seconds: 1));

      final thrown = await activate(() => fail('the wait never ended'),
              publicKeyCheck: unanswered, retryOptions: waitFor1s)
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(checks, greaterThan(1),
          reason: 'only a stop ends the wait early; an atServer that does not '
              'answer is asked again until the deadline');
      expect(thrown, isA<AtTimeoutException>(),
          reason: 'a wait that runs out says so; thrown: $thrown');
      expectNoKeysWritten();
    });
  });
}
