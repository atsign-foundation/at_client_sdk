import 'dart:convert';

import 'package:at_auth/at_auth.dart' show AtEnrollment;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeAtEnrollment extends Fake implements AtEnrollment {}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Catalogue: features/enrollment/approver_sees_expiry.feature
void main() {
  const atSign = '@alice';
  const b = 'b0b0b0b0-1a2e-43e4-93bd-378f1d366ea7';
  const enrollKey = '$b.new.enrollments.__manage$atSign';
  late MockAtClient client;
  late MockRemoteSecondary remote;
  late MockNotificationService notifications;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() {
    client = MockAtClient();
    remote = MockRemoteSecondary();
    notifications = MockNotificationService();
    when(() => client.getCurrentAtSign()).thenReturn(atSign);
    when(() => client.getRemoteSecondary()).thenReturn(remote);
    when(() => client.notificationService).thenReturn(notifications);
    when(() => client.enrollmentService)
        .thenReturn(EnrollmentServiceImpl(client, _FakeAtEnrollment()));
  });

  /// B's record as the atServer serves it, carrying no
  /// `apkamKeysExpiryInMillis` at all when [millis] is null.
  Map<String, dynamic> recordOfB(int? millis) => {
        'appName': 'wavi',
        'deviceName': 'phone',
        'namespace': {'wavi': 'rw'},
        'status': 'pending',
        if (millis != null) 'apkamKeysExpiryInMillis': millis,
      };

  /// Answers `enroll:list` with B, and refuses every other command.
  void serveList(Map<String, dynamic> record) {
    when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final String command = invocation.positionalArguments.first;
      if (!command.startsWith('enroll:list')) {
        throw StateError('this rig answers enroll:list only, not $command');
      }
      return 'data:${jsonEncode({enrollKey: record})}';
    });
  }

  /// Answers `enroll:fetch` with B, and refuses every other verb.
  void serveFetch(Map<String, dynamic> record) {
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final String command =
          (invocation.positionalArguments.first as VerbBuilder).buildCommand();
      if (!command.startsWith('enroll:fetch:')) {
        throw StateError('this rig answers enroll:fetch only, not $command');
      }
      return 'data:${jsonEncode(record)}';
    });
  }

  /// Announces B the way the atServer does, as a self notification.
  void announce(Map<String, dynamic> record) {
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => Stream.value(AtNotification('n-1', enrollKey, atSign,
            atSign, DateTime.now().millisecondsSinceEpoch, 'key', false)
          ..value = jsonEncode(record..remove('status'))));
  }

  group('An app sees the expiry a pending request asks for', () {
    test('1 hour, through client.enrollments.pending()', () async {
      serveList(recordOfB(3600000));

      final read = (await client.enrollments.pending()).single;

      expect(read.enrollmentId, b);
      expect(read.apkamKeysExpiryDuration, Duration(hours: 1));
    });

    test('1 hour, through client.enrollments.fetch(B)', () async {
      serveFetch(recordOfB(3600000));

      final read = await client.enrollments.fetch(b);

      expect(read?.apkamKeysExpiryDuration, Duration(hours: 1));
    });

    test('1 hour, through client.enrollments.requests', () async {
      announce(recordOfB(3600000));

      final read = await client.enrollments.requests.first;

      expect(read.enrollmentId, b);
      expect(read.apkamKeysExpiryDuration, Duration(hours: 1));
    });

    test('no expiry, through client.enrollments.pending()', () async {
      serveList(recordOfB(0));

      final read = (await client.enrollments.pending()).single;

      expect(read.apkamKeysExpiryDuration, Duration.zero);
    });
  });

  test('An atServer that does not report the requested expiry', () async {
    serveList(recordOfB(null));

    final read = (await client.enrollments.pending()).single;

    expect(read.appName, 'wavi',
        reason: 'the control: the rest of the record parsed');
    expect(read.apkamKeysExpiryDuration, isNull,
        reason: 'unknown, never "no expiry"');
  });
}
