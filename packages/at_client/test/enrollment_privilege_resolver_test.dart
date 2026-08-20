// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/enrollment_privilege_resolver.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_auth/at_auth.dart' show AtEnrollment;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

/// The record-backed resolver answers privilege questions from the
/// enrollment record — the server's word — for this client and for any
/// requester by id.
void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() => remoteData = {});

  MockAtClient clientWithRoster() {
    final client = buildRemoteBackedMockClient(
        atSign: atSign, enrollmentId: 'me-1', remoteData: remoteData);
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list)
        .buildCommand();
    final secondary = client.getRemoteSecondary()!;
    when(() => secondary.executeCommand(listCommand, auth: true))
        .thenAnswer((_) async => 'data:${jsonEncode({
                  'privileged-1.new.enrollments.__manage$atSign': {
                    'appName': 'admin',
                    'deviceName': 'desk',
                    'namespace': {'*': 'rw', '__manage': 'rw', 'buzz': 'rw'},
                  },
                  'scoped-1.new.enrollments.__manage$atSign': {
                    'appName': 'buzz',
                    'deviceName': 'pixel',
                    'namespace': {'buzz': 'rw'},
                  },
                })}');
    return client;
  }

  test('classifies a requester from its granted namespaces', () async {
    final client = clientWithRoster();
    final resolver = EnrollmentRecordPrivilegeResolver(client,
        listEnrollments: EnrollmentServiceImpl(client, AtEnrollment.create())
            .fetchEnrollmentRequests);

    expect(await resolver.isEnrollmentFullyPrivileged('privileged-1'), isTrue);
    expect(await resolver.isEnrollmentFullyPrivileged('scoped-1'), isFalse,
        reason: 'namespace-scoped is exactly the class the gate exists to '
            'refuse');
  });

  test('an enrollment the roster does not know is not privileged', () async {
    final client = clientWithRoster();
    final resolver = EnrollmentRecordPrivilegeResolver(client,
        listEnrollments: EnrollmentServiceImpl(client, AtEnrollment.create())
            .fetchEnrollmentRequests);

    expect(await resolver.isEnrollmentFullyPrivileged('unknown-9'), isFalse,
        reason: 'privilege is granted by the record; no record is no '
            'privilege');
  });
}
