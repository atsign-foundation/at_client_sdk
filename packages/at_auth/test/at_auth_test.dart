import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/file_io.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

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
      )..enrollmentId = testEnrollmentId;

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      final response = await atAuth.authenticate(atAuthRequest);

      expect(response.isSuccessful, true);
      expect(response.atAuthKeys!.enrollmentId, testEnrollmentId);
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
        ..enrollmentId = testEnrollmentId
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
      atAuthRequest.enrollmentId = testEnrollmentId;
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
      atAuthRequest.enrollmentId = testEnrollmentId;
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
      atAuthRequest.enrollmentId = testEnrollmentId;
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
      atAuthRequest.enrollmentId = testEnrollmentId;
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
      atAuthRequest.enrollmentId = testEnrollmentId;

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
      atAuthRequest.enrollmentId = testEnrollmentId;

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtAuthenticationException>()));
    });
  });
  group('AtAuthImpl onboarding tests', () {
    setUp(() {
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

      final atOnboardingRequest = AtOnboardingRequest('@aaron🛠');

      atAuth.secondaryAddressFinder = fakeSecondaryAddressFinder;
      atAuth.probeSocket = (host, port) async {};

      expect(
          () async => await atAuth.onboard(atOnboardingRequest, testCramSecret),
          throwsA(isA<AtAuthenticationException>()));
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
      final atOnboardingRequest = AtOnboardingRequest('@bob🛠')
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
      final atOnboardingRequest = AtOnboardingRequest('@colin🛠')
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
