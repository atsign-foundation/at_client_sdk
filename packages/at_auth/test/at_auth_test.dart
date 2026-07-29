import 'dart:io';

import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/io/ephemeral_io.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

class MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class MockAtServerStatus extends Mock implements AtServerStatus {}

class FakeVerbBuilder extends Fake implements VerbBuilder {}

class FakeAtLookUp extends Fake implements AtLookupImpl {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class FakeSecondaryAddressFinder extends Fake
    implements CacheableSecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    return SecondaryAddress('abcd', 123);
  }
}

void main() {
  late AtAuthImpl atAuth;
  late MockAtLookUp mockAtLookUp;
  late MockPkamAuthenticator mockPkamAuthenticator;
  late MockAtServerStatus mockAtServerStatus;
  late AtEnrollment mockAtEnrollment;
  late FileAtKeysIo fileAtKeysIo;
  final String testEnrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
  final alice = '@alice🛠'.toAtsign();
  late FakeSecondaryAddressFinder fakeSecondaryAddressFinder;

  // mocktail's fallback registry is process-global; registering once is enough.
  setUpAll(() {
    // Several tests assert a failure path, and AtAuthImpl logs those at SEVERE
    // with a stack trace. Quieten it so a green run reads as green.
    AtSignLogger.root_level = 'shout';
    registerFallbackValue(FakeVerbBuilder());
    registerFallbackValue(FakeEnrollmentRequest());
    registerFallbackValue(FakeAtLookUp());
    registerFallbackValue(legacyAtKeys());
  });

  setUp(() {
    // Reads the committed @alice🛠 fixture. Tests that *write* keys use their
    // own io over a temp dir, so nothing lands in test/data.
    fileAtKeysIo =
        FileAtKeysIo(filePath: (atsign) => 'test/data/${atsign}_key.atKeys');
  });

  /// Fresh mocks plus the stubs every test in either group needs: a reachable
  /// atServer of [serverStatus] and a closeable AtLookup.
  void buildAtAuth({required AtStatus atStatus}) {
    mockAtLookUp = MockAtLookUp();
    mockPkamAuthenticator = MockPkamAuthenticator();
    mockAtServerStatus = MockAtServerStatus();
    mockAtEnrollment = MockAtEnrollment();
    fakeSecondaryAddressFinder = FakeSecondaryAddressFinder();
    when(() => mockAtServerStatus.get(any()))
        .thenAnswer((_) => Future.value(atStatus));
    when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
    atAuth = AtAuthImpl(
        atLookUp: mockAtLookUp,
        pkamAuthenticator: mockPkamAuthenticator,
        atEnrollment: mockAtEnrollment,
        atServerStatus: mockAtServerStatus);
    atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
    atAuth.probeSocket = (host, port) async {};
  }

  group('AtAuthImpl authentication tests', () {
    setUp(() {
      buildAtAuth(
          atStatus: AtStatus(
              serverStatus: ServerStatus.ready,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.activated));
    });

    test('Test authenticate() with keys file returns the auth session',
        () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(), any(),
          enrollmentId: testEnrollmentId)).thenAnswer((_) async {});

      final atAuthRequest = AtAuthRequest(alice, fileAtKeysIo)
        ..enrollmentId = testEnrollmentId;

      final session = await atAuth.authenticate(atAuthRequest);

      expect(session.atsign, alice);
      expect(session.enrollmentId, testEnrollmentId);
      expect(session.rootDomain, AtRootDomain.atsignDomain);
      // The keys cross the boundary as a source, not as live AtChops: the
      // client re-reads them from the same AtKeysIo the request supplied.
      expect(session.atKeysIo, same(fileAtKeysIo));
      expect(session.atLookUp, same(mockAtLookUp));
    });

    test('Test authenticate() takes the enrollmentId from the keys file',
        () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(), any(),
          enrollmentId: any(named: 'enrollmentId'))).thenAnswer((_) async {});

      // The fixture keyfile carries this enrollmentId; the request leaves it
      // unset, so authenticate must fall back to the one in the keys.
      final session =
          await atAuth.authenticate(AtAuthRequest(alice, fileAtKeysIo));

      expect(session.enrollmentId, testEnrollmentId);
    });

    test('Test authenticate() with an in-memory AtKeysIo', () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(), any(),
          enrollmentId: testEnrollmentId)).thenAnswer((_) async {});

      // The modern replacement for handing AtKeys to the request directly:
      // supply them through an in-memory AtKeysIo.
      final memoryIo = EphemeralAtKeysIo();
      await memoryIo.write(alice, legacyAtKeys(atsign: alice));

      final session = await atAuth.authenticate(
        AtAuthRequest(alice, memoryIo)..enrollmentId = testEnrollmentId,
      );

      expect(session.atKeysIo, same(memoryIo));
      expect(session.enrollmentId, testEnrollmentId);
    });

    test('Test authenticate() invalid keys file path', () async {
      final atAuthRequest = AtAuthRequest(
        alice,
        FileAtKeysIo(filePath: (_) => 'test/hello/data/@alice🛠_key.atKeys'),
      )..enrollmentId = testEnrollmentId;

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtException>()));
    });

    test('Test authenticate() wraps a failed PKAM in AtAuthenticationException',
        () async {
      when(() => mockPkamAuthenticator.authenticate(any(), any(), any(),
              enrollmentId: testEnrollmentId))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));

      final atAuthRequest = AtAuthRequest(alice, fileAtKeysIo)
        ..enrollmentId = testEnrollmentId;

      await expectLater(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtAuthenticationException>()));
      // The connection we opened must not leak when authenticate throws.
      verify(() => mockAtLookUp.close()).called(1);
    });

    test(
        'validateAtServer honours overallTimeout instead of retrying until the '
        'network gives up', () async {
      // Every probe fails, so without a deadline validateAtServer would keep
      // retrying every retryDelay(2s). A short overallTimeout must cut that
      // short and surface an AtTimeoutException.
      atAuth.probeSocket = (host, port) async {
        throw Exception('simulated unreachable atServer');
      };
      final atAuthRequest = AtAuthRequest(alice, fileAtKeysIo)
        ..enrollmentId = testEnrollmentId
        ..retryOptions = const RetryOptions(
            retryDelay: Duration(seconds: 2),
            overallTimeout: Duration(milliseconds: 300));

      final sw = Stopwatch()..start();
      await expectLater(
        atAuth.validateAtServer(atAuthRequest),
        throwsA(isA<AtTimeoutException>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'should honour overallTimeout (300ms), not keep retrying');
    });
  });

  group('AtAuthImpl onboarding tests', () {
    var testCramSecret = 'cram123';
    // Onboarding mints and persists keys, so it gets a throwaway directory
    // rather than writing into the committed test/data.
    late Directory keysDir;
    late FileAtKeysIo onboardingKeysIo;

    setUp(() {
      keysDir = Directory.systemTemp.createTempSync('at_auth_onboard_test');
      addTearDown(() => keysDir.deleteSync(recursive: true));
      onboardingKeysIo = FileAtKeysIo(
          filePath: (atsign) => '${keysDir.path}/${atsign}_key.atKeys');
      buildAtAuth(
          atStatus: AtStatus(
              serverStatus: ServerStatus.teapot,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.teapot));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
    });

    /// Stubs the happy path: CRAM succeeds, the server approves the first
    /// enrollment as 'abc123', and PKAM succeeds.
    void stubSuccessfulOnboarding() {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(true));
      when(() =>
          mockAtLookUp.executeCommand(
              any(that: startsWith('enroll:request')))).thenAnswer((_) =>
          Future.value('data:{"enrollmentId":"abc123", "status":"approved"}'));
      when(() => mockPkamAuthenticator.authenticate(any(), any(), any(),
          enrollmentId: 'abc123')).thenAnswer((_) async {});
      when(() => mockAtEnrollment.submit(any(), mockAtLookUp))
          .thenAnswer((invocation) {
        // The first-enrollment response is scoped to the session onboarding is
        // establishing, which AtAuthImpl builds from the request.
        final request =
            invocation.positionalArguments.first as EnrollmentRequest;
        return Future.value(AtEnrollmentResponse(
          'abc123',
          EnrollmentStatus.approved,
          session: AtAuthSession(
            atsign: request.atsign,
            rootDomain: request.rootDomain,
            atKeysIo: onboardingKeysIo,
          ),
        ));
      });
    }

    test('Test onboard - cramAuthenticate returns false', () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(false));

      final atOnboardingRequest =
          AtOnboardingRequest('@aaron🛠'.toAtsign(), onboardingKeysIo);

      expect(
          () async => await atAuth.onboard(atOnboardingRequest, testCramSecret),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('Test onboard with appName and deviceName set in onboarding request',
        () async {
      stubSuccessfulOnboarding();
      final bob = '@bob🛠'.toAtsign();
      final atOnboardingRequest = AtOnboardingRequest(bob, onboardingKeysIo,
          appName: 'wavi', deviceName: 'iphone');

      final session = await atAuth.onboard(atOnboardingRequest, testCramSecret);

      expect(session.atsign, bob);
      expect(session.enrollmentId, 'abc123');
      // Onboarding persisted the freshly minted keys through the request's io.
      expect(session.atKeysIo, same(onboardingKeysIo));
      expect(File('${keysDir.path}/@bob🛠_key.atKeys').existsSync(), isTrue);
    });

    test('Test onboard with default appName and deviceName', () async {
      stubSuccessfulOnboarding();
      final colin = '@colin🛠'.toAtsign();
      final atOnboardingRequest = AtOnboardingRequest(colin, onboardingKeysIo);

      final session = await atAuth.onboard(atOnboardingRequest, testCramSecret);

      expect(atOnboardingRequest.appName, 'firstApp');
      expect(atOnboardingRequest.deviceName, 'firstDevice');
      expect(session.enrollmentId, 'abc123');
    });
  });
}
