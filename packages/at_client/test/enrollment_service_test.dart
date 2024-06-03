import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

import '../lib/src/service/enrollment_service_impl.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

void main() {
  group('A group of tests related to apkam/enrollments', () {
    test(
        'A test to verify enrollmentId is set in atClient after calling setCurrentAtSign',
        () async {
      final testEnrollmentId = 'abc123';
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign('@alice', 'wavi', AtClientPreference(),
              enrollmentId: testEnrollmentId);
      expect(atClientManager.atClient.enrollmentId, testEnrollmentId);
    });

    MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();

    test('verify behaviour of fetchEnrollmentRequests()', () async {
      String currentAtsign = '@apkam';
      String enrollKey1 =
          '0acdeb4d-1a2e-43e4-93bd-378f1d366ea7.new.enrollments.__manage$currentAtsign';
      String enrollValue1 =
          '{"appName":"buzz","deviceName":"pixel","namespace":{"buzz":"rw"}}';
      String enrollKey2 =
          '9beefa26-3384-4f10-81a6-0deaa4332669.new.enrollments.__manage$currentAtsign';
      String enrollValue2 =
          '{"appName":"buzz","deviceName":"pixel","namespace":{"buzz":"rw"}}';
      String enrollKey3 =
          'a6bbef17-c7bf-46f4-a172-1ed7b3b443bc.new.enrollments.__manage$currentAtsign';
      String enrollValue3 =
          '{"appName":"buzz","deviceName":"pixel","namespace":{"buzz":"rw"}}';
      String enrollListCommand = (EnrollVerbBuilder()
            ..operation = EnrollOperationEnum.list)
          .buildCommand();
      when(() =>
          mockRemoteSecondary.executeCommand(enrollListCommand,
              auth: true)).thenAnswer((_) => Future.value('data:{"$enrollKey1":'
          '$enrollValue1,"$enrollKey2":$enrollValue2,"$enrollKey3":$enrollValue3}'));

      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'buzz', AtClientPreference(),
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, atAuthBase.atEnrollment(currentAtsign));
      AtClientImpl? clientImpl = client as AtClientImpl;

      List<Enrollment> requests =
          await clientImpl.enrollmentService!.fetchEnrollmentRequests();
      expect(requests.length, 3);
      expect(requests[0].enrollmentId,
          enrollKey1.substring(0, enrollKey1.indexOf('.')));
      expect(requests[0].appName, jsonDecode(enrollValue1)['appName']);
      expect(requests[0].deviceName, jsonDecode(enrollValue1)['deviceName']);
      expect(requests[0].namespace, jsonDecode(enrollValue1)['namespace']);

      expect(requests[1].enrollmentId,
          enrollKey2.substring(0, enrollKey1.indexOf('.')));
      expect(requests[1].appName, jsonDecode(enrollValue2)['appName']);
      expect(requests[1].deviceName, jsonDecode(enrollValue2)['deviceName']);
      expect(requests[1].namespace, jsonDecode(enrollValue2)['namespace']);

      expect(requests[2].enrollmentId,
          enrollKey3.substring(0, enrollKey1.indexOf('.')));
      expect(requests[2].appName, jsonDecode(enrollValue3)['appName']);
      expect(requests[2].deviceName, jsonDecode(enrollValue3)['deviceName']);
      expect(requests[2].namespace, jsonDecode(enrollValue3)['namespace']);
    });

    test(
        'verify behaviour of fetchEnrollmentRequests() with enrollmentStatusFilter: [pending, approved]',
        () async {
      String currentAtsign = '@apkam1234';
      String enrollKey1 =
          '0acdeb4d-1a2e-43e4-93bd-random123.new.enrollments.__manage$currentAtsign';
      String enrollValue1 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      String enrollKey2 =
          '9beefa26-3384-4f10-81a6-random234.new.enrollments.__manage$currentAtsign';
      String enrollValue2 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      when(() =>
          mockRemoteSecondary.executeCommand(
              'enroll:list:{"enrollmentStatusFilter":["pending","approved"]}\n',
              auth: true)).thenAnswer((_) => Future.value('data:{"$enrollKey1":'
          '$enrollValue1,"$enrollKey2":$enrollValue2}'));

      EnrollmentListRequestParam listRequestParam = EnrollmentListRequestParam()
        ..enrollmentListFilter = [
          EnrollmentStatus.pending,
          EnrollmentStatus.approved
        ];
      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'random_namespace', AtClientPreference(),
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, atAuthBase.atEnrollment(currentAtsign));
      AtClientImpl? clientImpl = client as AtClientImpl;

      List<Enrollment> requests = await clientImpl.enrollmentService!
          .fetchEnrollmentRequests(enrollmentListParams: listRequestParam);
      expect(requests.length, 2);
      expect(requests[0].enrollmentId,
          enrollKey1.substring(0, enrollKey1.indexOf('.')));
      expect(requests[0].appName, jsonDecode(enrollValue1)['appName']);
      expect(requests[0].deviceName, jsonDecode(enrollValue1)['deviceName']);
      expect(requests[0].namespace, jsonDecode(enrollValue1)['namespace']);

      expect(requests[1].enrollmentId,
          enrollKey2.substring(0, enrollKey2.indexOf('.')));
      expect(requests[1].appName, jsonDecode(enrollValue2)['appName']);
      expect(requests[1].deviceName, jsonDecode(enrollValue2)['deviceName']);
      expect(requests[1].namespace, jsonDecode(enrollValue2)['namespace']);
    });

    test(
        'verify behaviour of fetchEnrollmentRequests() with enrollmentStatusFilter: [approved]',
        () async {
      String currentAtsign = '@apkam1234';
      String enrollKey1 =
          '0acdeb4d-1a2e-43e4-93bd-randomabc.new.enrollments.__manage$currentAtsign';
      String enrollValue1 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      String enrollKey2 =
          '9beefa26-3384-4f10-81a6-randomcde.new.enrollments.__manage$currentAtsign';
      String enrollValue2 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      when(() =>
          mockRemoteSecondary.executeCommand(
              'enroll:list:{"enrollmentStatusFilter":["approved"]}\n',
              auth: true)).thenAnswer((_) => Future.value('data:{"$enrollKey1":'
          '$enrollValue1,"$enrollKey2":$enrollValue2}'));

      EnrollmentListRequestParam listRequestParam = EnrollmentListRequestParam()
        ..enrollmentListFilter = [EnrollmentStatus.approved];
      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'random_namespace_1', AtClientPreference(),
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, atAuthBase.atEnrollment(currentAtsign));
      AtClientImpl? clientImpl = client as AtClientImpl;

      List<Enrollment> requests = await clientImpl.enrollmentService!
          .fetchEnrollmentRequests(enrollmentListParams: listRequestParam);
      expect(requests.length, 2);
      expect(requests[0].enrollmentId,
          enrollKey1.substring(0, enrollKey1.indexOf('.')));
      expect(requests[0].appName, jsonDecode(enrollValue1)['appName']);
      expect(requests[0].deviceName, jsonDecode(enrollValue1)['deviceName']);
      expect(requests[0].namespace, jsonDecode(enrollValue1)['namespace']);

      expect(requests[1].enrollmentId,
          enrollKey2.substring(0, enrollKey2.indexOf('.')));
      expect(requests[1].appName, jsonDecode(enrollValue2)['appName']);
      expect(requests[1].deviceName, jsonDecode(enrollValue2)['deviceName']);
      expect(requests[1].namespace, jsonDecode(enrollValue2)['namespace']);
    });
  });
}
