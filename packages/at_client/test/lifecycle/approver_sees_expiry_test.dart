import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show AtEnrollment, AtEnrollmentResponse, EnrollmentRequestDecision;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeAtEnrollment extends Fake implements AtEnrollment {}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Lists through the atServer as the real service does, and stands in for
/// the approval itself with [onApprove].
class _ApprovingService extends EnrollmentServiceImpl {
  final void Function(String enrollmentId) onApprove;

  _ApprovingService(super.atClient, super.atEnrollmentImpl, this.onApprove);

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    onApprove(enrollmentRequestDecision.enrollmentId);
    return AtEnrollmentResponse(
        enrollmentRequestDecision.enrollmentId, EnrollmentStatus.approved);
  }
}

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

  group('An atServer that serves an expiry of the wrong type', () {
    final whenBExpires = DateTime.utc(2026, 10, 17, 7);

    /// B's record carrying both expiry fields well typed, with [field] then
    /// set to [value].
    Map<String, dynamic> recordOfBWith(String field, Object value) =>
        recordOfB(3600000)
          ..['expiresAt'] = whenBExpires.toIso8601String()
          ..[field] = value;

    test(
        'apkamKeysExpiryInMillis the string "3600000", through '
        'client.enrollments.pending()', () async {
      serveList(recordOfBWith('apkamKeysExpiryInMillis', '3600000'));

      final read = (await client.enrollments.pending()).single;

      expect(read.appName, 'wavi');
      expect(read.expiresAt, whenBExpires,
          reason: 'the control: the record\'s other expiry field parsed');
      expect(read.apkamKeysExpiryDuration, isNull);
    });

    test(
        'apkamKeysExpiryInMillis the number 3600000.5, through '
        'client.enrollments.pending()', () async {
      serveList(recordOfBWith('apkamKeysExpiryInMillis', 3600000.5));

      final read = (await client.enrollments.pending()).single;

      expect(read.appName, 'wavi');
      expect(read.expiresAt, whenBExpires,
          reason: 'the control: the record\'s other expiry field parsed');
      expect(read.apkamKeysExpiryDuration, isNull);
    });

    test('apkamKeysExpiryInMillis true, through client.enrollments.fetch(B)',
        () async {
      serveFetch(recordOfBWith('apkamKeysExpiryInMillis', true));

      final read = await client.enrollments.fetch(b);

      expect(read?.appName, 'wavi');
      expect(read?.expiresAt, whenBExpires,
          reason: 'the control: the record\'s other expiry field parsed');
      expect(read?.apkamKeysExpiryDuration, isNull);
    });

    test(
        'apkamKeysExpiryInMillis the string "3600000", through '
        'client.enrollments.requests', () async {
      announce(recordOfB(null)..['apkamKeysExpiryInMillis'] = '3600000');

      final read = await client.enrollments.requests.first;

      expect(read.enrollmentId, b);
      expect(read.namespace, {'wavi': 'rw'},
          reason: 'the control: the rest of the record parsed');
      expect(read.apkamKeysExpiryDuration, isNull);
    });

    test(
        'expiresAt the number 1760684400000, through '
        'client.enrollments.pending()', () async {
      serveList(recordOfBWith('expiresAt', 1760684400000));

      final read = (await client.enrollments.pending()).single;

      expect(read.appName, 'wavi');
      expect(read.apkamKeysExpiryDuration, Duration(hours: 1),
          reason: 'the control: the record\'s other expiry field parsed');
      expect(read.expiresAt, isNull);
    });

    test('expiresAt the string "tomorrow", through client.enrollments.fetch(B)',
        () async {
      serveFetch(recordOfBWith('expiresAt', 'tomorrow'));

      final read = await client.enrollments.fetch(b);

      expect(read?.appName, 'wavi');
      expect(read?.apkamKeysExpiryDuration, Duration(hours: 1),
          reason: 'the control: the record\'s other expiry field parsed');
      expect(read?.expiresAt, isNull);
    });
  });

  late List<String> approvals;

  /// B's record as the atServer holds it: [pending] until B is approved,
  /// then [afterApproval], which is no record at all when null.
  late Map<String, dynamic> pending;
  late Map<String, dynamic>? afterApproval;

  /// Serves B pending until an approval, and [afterApproval] from then on.
  void serveApproval() {
    approvals = [];
    pending = recordOfB(3600000);
    afterApproval = recordOfB(3600000)..['status'] = 'approved';
    when(() => client.enrollmentService).thenReturn(_ApprovingService(
        client, _FakeAtEnrollment(), (id) => approvals.add(id)));
    // NOTE: the status filter is honoured, so a read that leaves out B's
    // status finds nothing.
    when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final String command = invocation.positionalArguments.first;
      final match =
          RegExp(r'^enroll:list(?::(\{.*\}))?\n$').firstMatch(command);
      if (match == null) {
        throw StateError('this rig answers enroll:list only, not $command');
      }
      final List? statuses = match.group(1) == null
          ? null
          : jsonDecode(match.group(1)!)['enrollmentStatusFilter'];
      final record = approvals.isEmpty ? pending : afterApproval;
      final served = record != null &&
          (statuses == null || statuses.contains(record['status']));
      return 'data:${jsonEncode({if (served) enrollKey: record})}';
    });
  }

  group('The approval returns B as the atServer holds it afterwards', () {
    final whenBExpires = DateTime.utc(2026, 10, 17, 7);

    setUp(serveApproval);

    /// Approves B, whose record after the approval carries [expiresAt],
    /// and checks it was approved once and read back approved.
    Future<Enrollment> approveBCarrying(Object? expiresAt) async {
      afterApproval!['expiresAt'] = expiresAt;
      final approved = await client.enrollments.approve(b);
      expect(approvals, [b], reason: 'B was approved, once');
      expect(approved.enrollmentId, b);
      expect(approved.enrollmentStatus, EnrollmentStatus.approved);
      return approved;
    }

    test('expiresAt "2026-10-17T07:00:00.000Z"', () async {
      final approved = await approveBCarrying('2026-10-17T07:00:00.000Z');

      expect(approved.expiresAt, whenBExpires);
    });

    test('expiresAt "2026-10-17T08:00:00.000+01:00"', () async {
      final approved = await approveBCarrying('2026-10-17T08:00:00.000+01:00');

      expect(approved.expiresAt, whenBExpires);
      expect(approved.expiresAt!.isUtc, isTrue);
    });

    test('expiresAt null', () async {
      final approved = await approveBCarrying(null);

      expect(approved.expiresAt, isNull);
    });

    test('no expiresAt', () async {
      final approved = await client.enrollments.approve(b);

      expect(afterApproval!.containsKey('expiresAt'), isFalse);
      expect(approvals, [b]);
      expect(approved.enrollmentStatus, EnrollmentStatus.approved);
      expect(approved.expiresAt, isNull);
    });

    test('expiresAt 1760684400000, a number', () async {
      final approved = await approveBCarrying(1760684400000);

      expect(approved.expiresAt, isNull);
    });

    test('expiresAt "tomorrow"', () async {
      final approved = await approveBCarrying('tomorrow');

      expect(approved.expiresAt, isNull);
    });
  });

  test(
      'The approval returns the term the atServer recorded, not the one '
      'asked for', () async {
    serveApproval();
    afterApproval!['apkamKeysExpiryInMillis'] = 1800000;

    final approved = await client.enrollments.approve(b);

    expect(approvals, [b]);
    expect(approved.apkamKeysExpiryDuration, Duration(minutes: 30));
  });

  test(
      'Another approver revokes B between the approval and the read after '
      'it', () async {
    serveApproval();
    afterApproval!['status'] = 'revoked';

    final approved = await client.enrollments.approve(b);

    expect(approvals, [b]);
    expect(approved.enrollmentStatus, EnrollmentStatus.revoked);
  });

  test('The atServer no longer holds B when it is read after the approval',
      () async {
    serveApproval();
    afterApproval = null;

    await expectLater(
        client.enrollments.approve(b),
        throwsA(isA<AtEnrollmentException>().having(
            (e) => e.message,
            'message',
            allOf(contains('approved enrollment $b'),
                contains('no longer holds it')))));
    expect(approvals, [b]);
  });
}
