import 'dart:convert';

import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/at_auth_request.dart';
import 'package:at_auth/src/auth/at_auth_response.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io_impl.dart';
import 'package:at_auth/src/onboard/at_onboarding_request.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// Create a mock for AtLookUp
class MockAtLookUp extends Mock implements AtLookupImpl {}

// Create a mock for AtChops
class MockAtChops extends Mock implements AtChops {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

class MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

class FakeDeleteVerbBuilder extends Fake implements DeleteVerbBuilder {}

class FakeVerbBuilder extends Fake implements VerbBuilder {}

void main() {
  late AtAuthImpl atAuth;
  late MockAtLookUp mockAtLookUp;
  late MockPkamAuthenticator mockPkamAuthenticator;
  late AtEnrollment mockAtEnrollment;
  final String testEnrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';

  setUp(() {
    mockAtLookUp = MockAtLookUp();
    mockPkamAuthenticator = MockPkamAuthenticator();
    mockAtEnrollment = MockAtEnrollment();
    atAuth = AtAuthImpl(
        atLookUp: mockAtLookUp,
        pkamAuthenticator: mockPkamAuthenticator,
        atEnrollmentBase: mockAtEnrollment);
    registerFallbackValue(FakeVerbBuilder());
  });
  group('AtAuthImpl authentication tests', () {
    test('Test authenticate() true with keys file', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() =>
          mockPkamAuthenticator.authenticate(
              enrollmentId: testEnrollmentId)).thenAnswer(
          (_) => Future.value(AtAuthResponse('@alice🛠')..isSuccessful = true));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        FileAtKeysIo(filePath: 'test/data/@alice🛠_key.atKeys'),
      );
      atAuthRequest.enrollmentId = testEnrollmentId;

      final response = await atAuth.authenticate(atAuthRequest);

      expect(response.isSuccessful, true);
      expect(response.atAuthKeys!.enrollmentId, testEnrollmentId);
    });

    test('Test authenticate() false with keys file', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(false));
      when(() => mockPkamAuthenticator.authenticate(
              enrollmentId: testEnrollmentId))
          .thenAnswer((_) =>
              Future.value(AtAuthResponse('@alice🛠')..isSuccessful = false));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        FileAtKeysIo(filePath: 'test/data/@alice🛠_key.atKeys'),
      );
      atAuthRequest.enrollmentId = testEnrollmentId;

      final response = await atAuth.authenticate(atAuthRequest);

      expect(response.isSuccessful, false);
      expect(response.atAuthKeys!.enrollmentId, testEnrollmentId);
    });

    test('Test authenticate() invalid keys file path', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() =>
          mockPkamAuthenticator.authenticate(
              enrollmentId: testEnrollmentId)).thenAnswer(
          (_) => Future.value(AtAuthResponse('@alice🛠')..isSuccessful = true));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        FileAtKeysIo(filePath: 'test/data/hello/@alice🛠_key.atKeys'),
      );
      atAuthRequest.enrollmentId = testEnrollmentId;
      atAuthRequest.atKeysIo =
          FileAtKeysIo(filePath: 'test/data/hello/@alice🛠_key.atKeys');

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtException>()));
    });

    test('Test authenticate() with atAuthKeys set', () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() =>
          mockPkamAuthenticator.authenticate(
              enrollmentId: testEnrollmentId)).thenAnswer(
          (_) => Future.value(AtAuthResponse('@alice🛠')..isSuccessful = true));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        FileAtKeysIo(filePath: 'test/data/hello/@alice🛠_key.atKeys'),
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

      final response = await atAuth.authenticate(atAuthRequest);

      expect(response.isSuccessful, true);
      expect(response.atAuthKeys!.enrollmentId, testEnrollmentId);
    });

    test(
        'Test authenticate() - throw exception is pkamPrivateKey is not set for default auth mode.',
        () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenAnswer((_) => Future.value(true));
      when(() =>
          mockPkamAuthenticator.authenticate(
              enrollmentId: testEnrollmentId)).thenAnswer(
          (_) => Future.value(AtAuthResponse('@alice🛠')..isSuccessful = true));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        FileAtKeysIo(filePath: 'test/data/hello/@alice🛠_key.atKeys'),
      );
      atAuthRequest.enrollmentId = testEnrollmentId;
      atAuthRequest.atAuthKeys = AtKeys()
        ..apkamPublicKey =
            AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
        ..defaultEncryptionPublicKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPublicKey')))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
        ..defaultSelfEncryptionKey = AtBytes.fromString(
            base64Encode(utf8.encode('defaultSelfEncryptionKey')))
        ..enrollmentId = testEnrollmentId;

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
        FileAtKeysIo(filePath: 'test/data/hello/@alice🛠_key.atKeys'),
      );
      atAuthRequest.enrollmentId = testEnrollmentId;

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtAuthenticationException>()));
    });

    test(
        'Test authenticate() pkamAuthenticate method throws UnAuthenticatedException',
        () async {
      when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: testEnrollmentId))
          .thenThrow(UnAuthenticatedException('Unauthenticated'));
      when(() => mockPkamAuthenticator.authenticate(
              enrollmentId: testEnrollmentId))
          .thenThrow(AtAuthenticationException('Unauthenticated'));
      final atAuthRequest = AtAuthRequest(
        '@alice🛠',
        FileAtKeysIo(filePath: 'test/data/hello/@alice🛠_key.atKeys'),
      );
      atAuthRequest.enrollmentId = testEnrollmentId;

      expect(() async => await atAuth.authenticate(atAuthRequest),
          throwsA(isA<AtAuthenticationException>()));
    });
  });
  group('AtAuthImpl onboarding tests', () {
    var testCramSecret = 'cram123';
    test('Test onboard - cramAuthenticate returns false', () async {
      when(() => mockAtLookUp.cramAuthenticate(testCramSecret))
          .thenAnswer((_) => Future.value(false));
      when(() => mockAtLookUp.executeCommand(any()))
          .thenAnswer((_) => Future.value('data:1'));
      when(() => mockAtLookUp.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:2'));

      when(() => mockAtLookUp.close()).thenAnswer((_) async => {});
      when(() => mockPkamAuthenticator.authenticate()).thenAnswer(
          (_) => Future.value(AtAuthResponse('@alice🛠')..isSuccessful = true));

      final atOnboardingRequest = AtOnboardingRequest('@alice🛠')
        ..rootDomain = AtRootDomain('test.atsign.com', 64);

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
      when(() => mockPkamAuthenticator.authenticate(enrollmentId: "abc123"))
          .thenAnswer((_) =>
              Future.value(AtAuthResponse('@alice🛠')..isSuccessful = true));
      final mockEnrollmentResponse =
          AtEnrollmentResponse("abc123", EnrollmentStatus.approved);
      when(() => mockAtEnrollment.submit(any(), mockAtLookUp))
          .thenAnswer((_) => Future.value(mockEnrollmentResponse));
      final atOnboardingRequest = AtOnboardingRequest('@alice🛠')
        ..rootDomain = AtRootDomain('test.atsign.com', 64)
        ..appName = 'wavi'
        ..deviceName = 'iphone';

      final response =
          await atAuth.onboard(atOnboardingRequest, testCramSecret);

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
      when(() => mockPkamAuthenticator.authenticate(enrollmentId: "abc123"))
          .thenAnswer((_) =>
              Future.value(AtAuthResponse('@alice🛠')..isSuccessful = true));
      final mockEnrollmentResponse =
          AtEnrollmentResponse("abc123", EnrollmentStatus.approved);
      when(() => mockAtEnrollment.submit(any(), mockAtLookUp))
          .thenAnswer((_) => Future.value(mockEnrollmentResponse));
      final atOnboardingRequest = AtOnboardingRequest('@alice🛠')
        ..rootDomain = AtRootDomain('test.atsign.com', 64);
      final response =
          await atAuth.onboard(atOnboardingRequest, testCramSecret);

      expect(response.isSuccessful, true);
      expect(response.enrollmentId, 'abc123');
    });
  });
}
