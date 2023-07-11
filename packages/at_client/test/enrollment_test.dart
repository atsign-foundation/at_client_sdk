import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/enrollment/enrollment_request.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

String atSign = '@bob';
String namespace = 'wavi';
AtClientPreference atClientPreference = AtClientPreference();

void main() {
  RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
  group('A group of tests related to enrollment request', () {
    test('A test to verify enrollment request and response', () async {
      when(() => mockRemoteSecondary.executeCommand(
              any(that: startsWith('enroll:request')),
              auth: true))
          .thenAnswer((_) => Future.value(
              jsonEncode({'enrollmentId': '123', 'status': 'success'})));

      Enrollment enrollment = Enrollment.request()
          .setAppName('wavi')
          .setDeviceName('mydevice')
          .setNamespaces(['wavi,rw', 'buzz,r'])
          .setAPKAMPublicKey('dummy_public_key')
          .build();
      AtClient atClient = await AtClientImpl.create(
          atSign, namespace, atClientPreference,
          remoteSecondary: mockRemoteSecondary);
      EnrollmentResponse enrollmentResponse = await atClient.enroll(enrollment);
      expect(enrollmentResponse.enrollmentId, '123');
      expect(enrollmentResponse.enrollStatus, 'success');
    });

    test('A test to verify fetch otp from server', () async {
      when(() => mockRemoteSecondary
              .executeCommand(any(that: startsWith('totp:get'))))
          .thenAnswer((_) => Future.value('987567'));

      AtClientImpl atClient = await AtClientImpl.create(
          atSign, namespace, atClientPreference,
          remoteSecondary: mockRemoteSecondary) as AtClientImpl;
      String otp = await atClient.getOTP();
      expect(otp, '987567');
    });
    tearDown(() {
      resetMocktailState();
    });
  });

  group('A group of tests to approve the enrollment', () {
    test('A test to verify approve scenario', () async {
      when(() => mockRemoteSecondary
          .executeCommand(any(that: startsWith('enroll:approve')),
              auth: true)).thenAnswer(
          (_) => Future.value('data:${jsonEncode({'status': 'approved'})}'));

      AtClient atClient = await AtClientImpl.create(
          atSign, namespace, atClientPreference,
          remoteSecondary: mockRemoteSecondary);

      Enrollment enrollment =
          Enrollment.approve().setEnrollmentId(987567).build();
      EnrollmentResponse enrollmentResponse = await atClient.enroll(enrollment);
      expect(enrollmentResponse.enrollStatus, 'approved');
    });
    tearDown(() {
      resetMocktailState();
    });
  });

  group('A group of tests to deny the enrollment', () {
    test('A test to verify deny scenario', () async {
      when(() => mockRemoteSecondary
              .executeCommand(any(that: startsWith('enroll:deny')), auth: true))
          .thenAnswer(
              (_) => Future.value('data:${jsonEncode({'status': 'denied'})}'));

      AtClient atClient = await AtClientImpl.create(
          atSign, namespace, atClientPreference,
          remoteSecondary: mockRemoteSecondary);

      Enrollment enrollment = Enrollment.deny().setEnrollmentId(987567).build();
      EnrollmentResponse enrollmentResponse = await atClient.enroll(enrollment);
      expect(enrollmentResponse.enrollStatus, 'denied');
    });
    tearDown(() {
      resetMocktailState();
    });
  });
}
