import 'dart:io';

import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/retry_options.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_auth/src/keys/io/memory_io.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

/// Runs an installed [AtAuthenticator] for real and records what it sent.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}

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
  late FakeSecondaryAddressFinder fakeSecondaryAddressFinder;

  setUp(() {
    fileAtKeysIo =
        FileAtKeysIo(filePath: (atsign) => 'test/data/${atsign}_key.atKeys');
    registerFallbackValue(FakeVerbBuilder());
    registerFallbackValue(FakeEnrollmentRequest());
    registerFallbackValue(FakeAtLookUp());
  });
  group('AtAuthImpl onboarding tests', () {
    setUp(() {
      // Fresh mocks per test: without these the group only runs after the
      // authentication group has initialized the shared `late` variables.
      mockAtLookUp = MockAtLookUp();
      mockPkamAuthenticator = MockPkamAuthenticator();
      mockAtEnrollment = MockAtEnrollment();
      fakeSecondaryAddressFinder = FakeSecondaryAddressFinder();
      mockAtServerStatus = MockAtServerStatus();
      when(() => mockAtServerStatus.get(any())).thenAnswer((_) => Future.value(
          AtStatus(
              serverStatus: ServerStatus.teapot,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.teapot)));
      atAuth = AtAuthImpl(
          atLookUp: mockAtLookUp,
          pkamAuthenticator: mockPkamAuthenticator,
          atEnrollment: mockAtEnrollment,
          atServerStatus: mockAtServerStatus);
    });
    var testCramSecret = 'cram123';

    test(
        'validateAtServer honours overallTimeout instead of running all retries',
        () async {
      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      // Every probe fails, so without a deadline validateAtServer would retry
      // maxRetries(10) x retryDelay(2s) ~= 20s. A short overallTimeout must cut
      // that short and surface an AtTimeoutException.
      atAuth.probeSocket = (host, port) async {
        throw Exception('simulated unreachable atServer');
      };
      final request = AtOnboardingRequest('@alice🛠',
          signingAlgoType: SigningAlgoType.rsa2048,
          atKeysIo: fileAtKeysIo,
          retryOptions: const RetryOptions(
              maxRetries: 10,
              retryDelay: Duration(seconds: 2),
              overallTimeout: Duration(milliseconds: 300)));

      final sw = Stopwatch()..start();
      await expectLater(
        atAuth.validateAtServer(request),
        throwsA(isA<AtTimeoutException>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'should honour overallTimeout (300ms), not 10 x 2s retries');
    });

    test('Test onboard - cramAuthenticate returns false', () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(false));
      when(() => mockAtLookUp.executeCommand(any()))
          .thenAnswer((_) => Future.value('data:1'));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: "abc123")).thenAnswer((_) => Future.value(true));

      final atOnboardingRequest = AtOnboardingRequest('@aaron🛠',
          signingAlgoType: SigningAlgoType.rsa2048);

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      expect(
          () async => await atAuth.onboard(atOnboardingRequest, testCramSecret),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('an enrollment refusal surfaces the underlying reason in the message',
        () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
      when(() => mockAtEnrollment.submit(any(), mockAtLookUp)).thenThrow(
          AtEnrollmentException('server refused: enrollment quota exceeded'));

      final atOnboardingRequest = AtOnboardingRequest('@ferris🛠',
          signingAlgoType: SigningAlgoType.rsa2048)
        ..atKeysIo = fileAtKeysIo
        ..appName = 'wavi'
        ..deviceName = 'iphone';

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      // The person reading this exception is mid-failure; the wrapped
      // message is the only clue they get about what the server said.
      expect(
          () => atAuth.onboard(atOnboardingRequest, testCramSecret),
          throwsA(isA<AtAuthenticationException>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('enrollment quota exceeded'),
                  isNot(contains('Closure'))))));
    });

    test('Test onboard with appName and deviceName set in onboarding request',
        () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
      when(() =>
          mockAtLookUp.executeCommand(
              any(that: startsWith('enroll:request')))).thenAnswer((_) =>
          Future.value('data:{"enrollmentId":"abc123", "status":"approved"}'));

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: "abc123")).thenAnswer((_) => Future.value(true));
      final mockEnrollmentResponse =
          AtEnrollmentResponse("abc123", EnrollmentStatus.approved);
      when(() => mockAtEnrollment.submit(any(), mockAtLookUp))
          .thenAnswer((_) => Future.value(mockEnrollmentResponse));
      final atOnboardingRequest = AtOnboardingRequest('@bob🛠',
          signingAlgoType: SigningAlgoType.rsa2048)
        ..atKeysIo = fileAtKeysIo
        ..appName = 'wavi'
        ..deviceName = 'iphone';

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      final response = await atAuth.onboard(
        atOnboardingRequest,
        testCramSecret,
      );

      expect(response.isSuccessful, true);
      expect(response.enrollmentId, 'abc123');
    });
    test('the activation PKAM names the enrollment the atServer just assigned',
        () async {
      // `onboard` installs the authenticator BEFORE the enrollment exists, so
      // that first one closes over a null enrollment id - correct at that
      // moment, since the connection is CRAM-authenticated. It has to be
      // reinstalled once the atServer names the enrollment, because
      // `enrollmentId` is captured at install time and never re-read: without
      // that, the activation PKAM goes out with no `enrollmentId:` segment
      // however the id is passed to `pkamAuthenticate`, the atServer
      // authenticates the connection as `pkamLegacy` against the default PKAM
      // public key, and the two ends disagree about who is on the connection.
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: 'abc123')).thenAnswer((_) => Future.value(true));
      when(() => mockAtEnrollment.submit(any(), mockAtLookUp)).thenAnswer((_) =>
          Future.value(
              AtEnrollmentResponse('abc123', EnrollmentStatus.approved)));

      final atOnboardingRequest = AtOnboardingRequest('@alice🛠',
          signingAlgoType: SigningAlgoType.rsa2048)
        ..atKeysIo = InMemoryAtKeysIo()
        ..appName = 'wavi'
        ..deviceName = 'iphone';
      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      await atAuth.onboard(atOnboardingRequest, testCramSecret);

      final installed = verify(() => mockAtLookUp.authenticator = captureAny())
          .captured
          .cast<AtAuthenticator>();

      // The authenticator in force when the activation PKAM runs is the last
      // one installed. Run it for real against demo material.
      const challenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581@alice🛠'
          ':c3d345fc-5691-4f90-bc34-17cba31f060f';
      final executor = _RecordingExecutor(['data:$challenge', 'data:success']);
      expect(await installed.last(executor), isTrue);
      final pkam = executor.sent.last;

      expect(pkam, contains(':enrollmentId:abc123:'),
          reason: 'the activation PKAM must name the enrollment the atServer '
              'assigned, or the atServer authenticates it as pkamLegacy while '
              'at_lookup records it as this enrollment');

      // The control, and it is what makes this discriminate: the FIRST
      // authenticator legitimately carries no id, because none existed when it
      // was installed. Asserting only on the last one would pass if the
      // reinstall were dropped and the first one happened to be right.
      final firstExecutor =
          _RecordingExecutor(['data:$challenge', 'data:success']);
      await installed.first(firstExecutor);
      expect(firstExecutor.sent.last, isNot(contains(':enrollmentId:')),
          reason: 'nothing had named the enrollment when this was installed');
      expect(installed.length, greaterThanOrEqualTo(2),
          reason: 'the reinstall is the fix; one install means it was dropped');
    });

    test('Test onboard with default appName and deviceName', () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));
      when(() =>
          mockAtLookUp.executeCommand(
              any(that: startsWith('enroll:request')))).thenAnswer((_) =>
          Future.value('data:{"enrollmentId":"abc123", "status":"approved"}'));

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
          enrollmentId: "abc123")).thenAnswer((_) => Future.value(true));
      final mockEnrollmentResponse =
          AtEnrollmentResponse("abc123", EnrollmentStatus.approved);
      when(() => mockAtEnrollment.submit(any(), mockAtLookUp))
          .thenAnswer((_) => Future.value(mockEnrollmentResponse));
      final atOnboardingRequest = AtOnboardingRequest('@colin🛠',
          signingAlgoType: SigningAlgoType.rsa2048)
        ..atKeysIo = fileAtKeysIo;

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      final response = await atAuth.onboard(
        atOnboardingRequest,
        testCramSecret,
      );

      expect(response.isSuccessful, true);
      expect(response.enrollmentId, 'abc123');
    });

    tearDownAll(() {
      final bobKeys = File('test/data/@bob🛠_key.atKeys');
      final colinKeys = File('test/data/@colin🛠_key.atKeys');
      if (bobKeys.existsSync()) {
        bobKeys.deleteSync();
      }
      if (colinKeys.existsSync()) {
        colinKeys.deleteSync();
      }
    });
  });
}
