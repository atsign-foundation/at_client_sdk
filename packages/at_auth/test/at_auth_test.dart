import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
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
  final String testEnrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
  late FakeSecondaryAddressFinder fakeSecondaryAddressFinder;

  setUp(() {
    fileAtKeysIo =
        FileAtKeysIo(filePath: (atsign) => 'test/data/${atsign}_key.atKeys');
    registerFallbackValue(FakeVerbBuilder());
    registerFallbackValue(FakeEnrollmentRequest());
    registerFallbackValue(FakeAtLookUp());
  });
  group('AtAuthImpl authentication tests', () {
    setUp(() {
      mockAtLookUp = MockAtLookUp();
      mockPkamAuthenticator = MockPkamAuthenticator();
      mockAtServerStatus = MockAtServerStatus();
      fakeSecondaryAddressFinder = FakeSecondaryAddressFinder();
      mockAtEnrollment = MockAtEnrollment();
      when(() => mockAtServerStatus.get(any())).thenAnswer((_) => Future.value(
          AtStatus(
              serverStatus: ServerStatus.ready,
              rootStatus: RootStatus.found,
              atSignStatus: AtSignStatus.activated)));
      atAuth = AtAuthImpl(
          atLookUp: mockAtLookUp,
          pkamAuthenticator: mockPkamAuthenticator,
          atEnrollment: mockAtEnrollment,
          atServerStatus: mockAtServerStatus);
    });

    test('Test authenticate() true with keys file', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
              enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));

      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        atKeysIo: fileAtKeysIo,
      );

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      final response = await atAuth.authenticate(atAuthRequest);

      expect(response.isSuccessful, true);
      expect(response.atAuthKeys!.enrollmentId, testEnrollmentId);
    });

    /// A retrofitted keyfile: the flat fields keep the legacy enrollment's
    /// credentials, the typed section carries the successor's. The one shape
    /// where "the flat id" and "the derived id" are both real and differ.
    Future<InMemoryAtKeysIo> retrofittedKeyfile() async {
      final keysIo = InMemoryAtKeysIo();
      await keysIo.write(
          '@alice',
          AtKeys()
            ..apkamPublicKey = AtBytes.fromString(
                base64Encode(utf8.encode('legacy-rsa-public')))
            ..apkamPrivateKey = AtBytes.fromString(
                base64Encode(utf8.encode('legacy-rsa-private')))
            ..defaultEncryptionPublicKey =
                AtBytes.fromString(base64Encode(utf8.encode('enc-public')))
            ..defaultEncryptionPrivateKey =
                AtBytes.fromString(base64Encode(utf8.encode('enc-private')))
            ..defaultSelfEncryptionKey =
                AtBytes.fromString(base64Encode(utf8.encode('self-key')))
            ..enrollmentId = 'legacy-1');

      // Retrofit it for real rather than hand-building the end state: a
      // hand-assembled document is a claim about what a retrofit produces,
      // and this test is about what `authenticate` does with the real thing.
      final approving = MockAtLookUp();
      when(() =>
          approving.executeCommand(any(that: startsWith('enroll:')),
              auth: any(named: 'auth'))).thenAnswer(
          (_) async => 'data:{"enrollmentId":"new-123","status":"approved"}');
      await AtEnrollmentImpl().submit(
          AtSelfEnrollmentRequest(
              session: AtAuthSession(
                  atSign: '@alice',
                  rootDomain: AtRootDomain.atsignDomain,
                  atKeysIo: keysIo,
                  enrollmentId: 'legacy-1'),
              appName: 'selfapp',
              deviceName: 'selfdevice',
              namespaces: {'app_1': 'rw'}),
          approving);

      // NOTE: the two sources must disagree, or the test below passes for a
      // reason that has nothing to do with which one authenticate read.
      final retrofitted = await keysIo.read('@alice'.toAtsign());
      // ignore: deprecated_member_use_from_same_package
      expect(retrofitted.enrollmentId, 'legacy-1');
      expect(retrofitted.resolveAuthenticatingEnrollment(), 'new-123',
          reason: 'the two sources must give different, non-null answers or '
              'this fixture discriminates nothing');
      return keysIo;
    }

    /// The enrollment id that reached `PkamAuthenticator.authenticate` — what
    /// actually signs the PKAM challenge, rather than what the document says.
    Future<String?> idReachingPkam(AtKeysIo keysIo,
        {String atSign = '@alice'}) async {
      final authenticator = MockPkamAuthenticator();
      when(() => authenticator.authenticate(any(), any(),
              enrollmentId: any(named: 'enrollmentId')))
          .thenAnswer((_) async => true);
      final auth = AtAuthImpl(
          atLookUp: MockAtLookUp(),
          pkamAuthenticator: authenticator,
          atEnrollment: mockAtEnrollment,
          atServerStatus: mockAtServerStatus)
        ..secondaryAddressFinder = fakeSecondaryAddressFinder
        ..probeSocket = ((host, port) async {});
      await auth.authenticate(AtAuthRequest(atSign, atKeysIo: keysIo));
      return verify(() => authenticator.authenticate(any(), any(),
              enrollmentId: captureAny(named: 'enrollmentId'))).captured.single
          as String?;
    }

    test('a legacy keyfile authenticates as its flat stored enrollment',
        () async {
      // UC-G1.1: the keys decide.
      final atKeys = await fileAtKeysIo.read('@alice🛠'.toAtsign());
      expect(atKeys.resolveAuthenticatingEnrollment(), isNull,
          reason: 'the fixture holds no typed authentication material, so '
              'the id that reaches pkam can only have come from the flat '
              'field');
      expect(await idReachingPkam(fileAtKeysIo, atSign: '@alice🛠'),
          testEnrollmentId);
    });

    test(
        'a RETROFITTED keyfile authenticates as the successor, not the flat '
        'legacy enrollment', () async {
      expect(await idReachingPkam(await retrofittedKeyfile()), 'new-123',
          reason: 'the retrofit exists to move the client to its successor; '
              'the flat field still names legacy-1, and reading it would sign '
              'the PKAM challenge as the enrollment the successor replaced');
    });

    test('an ancient keyfile with no enrollment id authenticates as primary',
        () async {
      // For a keyfile with no stored id, `primary` is the atServer's name for
      // that credential; the verb builder keeps it off the wire.
      final keysIo = InMemoryAtKeysIo();
      await keysIo.write(
          '@alice',
          AtKeys()
            ..apkamPublicKey = AtBytes.fromString(
                base64Encode(utf8.encode('legacy-rsa-public')))
            ..apkamPrivateKey = AtBytes.fromString(
                base64Encode(utf8.encode('legacy-rsa-private')))
            ..defaultEncryptionPublicKey =
                AtBytes.fromString(base64Encode(utf8.encode('enc-public')))
            ..defaultEncryptionPrivateKey =
                AtBytes.fromString(base64Encode(utf8.encode('enc-private')))
            ..defaultSelfEncryptionKey =
                AtBytes.fromString(base64Encode(utf8.encode('self-key'))));
      expect(await idReachingPkam(keysIo), 'primary');
    });

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
      final atAuthRequest = AtAuthRequest('@alice🛠', atKeysIo: fileAtKeysIo)
        ..retryOptions = const RetryOptions(
            maxRetries: 10,
            retryDelay: Duration(seconds: 2),
            overallTimeout: Duration(milliseconds: 300));

      final sw = Stopwatch()..start();
      await expectLater(
        atAuth.validateAtServer(atAuthRequest),
        throwsA(isA<AtTimeoutException>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'should honour overallTimeout (300ms), not 10 x 2s retries');
    });

    test('Test authenticate() false with keys file', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(false));
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
              enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(false));

      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        atKeysIo: fileAtKeysIo,
      );
      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      final response = await atAuth.authenticate(atAuthRequest);

      expect(response.isSuccessful, false);
      expect(response.atAuthKeys!.enrollmentId, testEnrollmentId);
    });

    test('Test authenticate() invalid keys file path', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
              enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));

      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        atKeysIo: FileAtKeysIo(
            filePath: (_) => 'test/hello/data/@alice🛠_key.atKeys'),
      );
      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtException>()));
    });

    test('Test authenticate() with atAuthKeys set', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
              enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        atKeysIo: fileAtKeysIo,
      );
      atAuthRequest.atAuthKeys = AtKeys()
        ..apkamPublicKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
        ..apkamPrivateKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPrivateKey')))
        ..defaultEncryptionPublicKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPublicKey')))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
        ..defaultSelfEncryptionKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultSelfEncryptionKey')))
        ..enrollmentId = testEnrollmentId;

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      final response = await atAuth.authenticate(atAuthRequest);

      expect(response.isSuccessful, true);
      expect(response.atAuthKeys!.enrollmentId, testEnrollmentId);
    });

    test(
        'Test authenticate() - throw exception is pkamPrivateKey is not set for default auth mode.',
        () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
              enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        atKeysIo: fileAtKeysIo,
      );
      atAuthRequest.atAuthKeys = AtKeys()
        ..defaultEncryptionPublicKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPublicKey')))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
        ..defaultSelfEncryptionKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultSelfEncryptionKey')))
        ..enrollmentId = testEnrollmentId;

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtPrivateKeyNotFoundException>()));
    });

    test(
        'Test authenticate throws exception when keysfile path and atAuthKeys is not set in request',
        () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        atKeysIo: fileAtKeysIo,
      );

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtAuthenticationException>()));
    });

    test(
        'Test authenticate() pkamAuthenticate method throws UnAuthenticatedException',
        () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));
      when(() => mockPkamAuthenticator.authenticate(any(), any(),
              enrollmentId: testEnrollmentId))
          .thenThrow(AtAuthenticationException('Unauthenticated'));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        atKeysIo: fileAtKeysIo,
      );

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtAuthenticationException>()));
    });
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
