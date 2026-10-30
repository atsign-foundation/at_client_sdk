import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show AtEnrollmentResponse, EnrollmentRequestDecision;
import 'package:at_client/at_client.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;
import 'package:at_client_cli/src/commands/auth_cli_args.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockEnrollmentService extends Mock implements EnrollmentService {}

class _MockNotificationService extends Mock implements NotificationService {}

class _FakeListParams extends Fake implements EnrollmentListRequestParam {}

class _FakeDecision extends Fake implements EnrollmentRequestDecision {}

/// Collects what `at_activate` prints.
class _CapturedStdout extends Fake implements Stdout {
  final List<String> written = [];

  String get text => written.join();

  @override
  void write(Object? object) => written.add('$object');

  @override
  void writeln([Object? object = '']) => written.add('$object\n');
}

/// Catalogue: features/enrollment/approver_sees_expiry.feature
/// Catalogue: features/at_client_cli/auto_approve_keeps_listening.feature
void main() {
  const b = 'b0b0b0b0-1a2e-43e4-93bd-378f1d366ea7';
  late _MockAtClient client;
  late _MockEnrollmentService service;
  late List<String> approvals;

  setUpAll(() {
    registerFallbackValue(_FakeListParams());
    registerFallbackValue(_FakeDecision());
  });

  /// Serves B as pending until it is approved, then with [statusAfter] and
  /// [expiresAt], or with no expiresAt at all when that is null.
  void serveB({String? expiresAt, String statusAfter = 'approved'}) {
    client = _MockAtClient();
    service = _MockEnrollmentService();
    approvals = [];
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.enrollmentService).thenReturn(service);
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [
              Enrollment.fromJSON({
                'appName': 'wavi',
                'deviceName': 'phone',
                'namespace': {'wavi': 'rw'},
                'status': approvals.isEmpty ? 'pending' : statusAfter,
                'apkamKeysExpiryInMillis': 3600000,
                if (approvals.isNotEmpty && expiresAt != null)
                  'expiresAt': expiresAt,
              })
                ..enrollmentId = b
            ]);
    when(() => service.approve(any())).thenAnswer((invocation) async {
      final EnrollmentRequestDecision decision =
          invocation.positionalArguments.first;
      approvals.add(decision.enrollmentId);
      return AtEnrollmentResponse(
          decision.enrollmentId, EnrollmentStatus.approved);
    });
  }

  /// Runs `at_activate auto_approve` until it has approved B, announced as
  /// the atServer announces a new request, and hands back what it printed.
  Future<_CapturedStdout> autoApproveB(
      {String appName = 'wavi', String deviceName = 'phone'}) async {
    final notifications = _MockNotificationService();
    when(() => client.notificationService).thenReturn(notifications);
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => Stream.value(AtNotification(
            'n-1',
            '$b.new.enrollments.__manage@alice',
            '@alice',
            '@alice',
            DateTime.now().millisecondsSinceEpoch,
            'key',
            false)
          ..value =
              jsonEncode({'appName': appName, 'deviceName': deviceName})));
    final args = AuthCliArgs().createAutoApproveCommandParser().parse([
      '-a',
      '@alice',
      '--${AuthCliArgs.argNameAppNameRegex}',
      'wavi',
      '--${AuthCliArgs.argNameDeviceNameRegex}',
      'phone',
    ]);
    final out = _CapturedStdout();
    await IOOverrides.runZoned(() => auth_cli.autoApprove(args, client),
        stdout: () => out);
    return out;
  }

  group('at_activate prints when an enrollment it approves expires', () {
    test('approve', () async {
      serveB(expiresAt: '2026-10-17T07:00:00.000Z');
      final args = AuthCliArgs().createApproveCommandParser().parse(
          ['-a', '@alice', '--${AuthCliArgs.argNameAppNameRegex}', 'wavi']);
      final out = _CapturedStdout();

      await IOOverrides.runZoned(() => auth_cli.approve(args, client),
          stdout: () => out);

      expect(approvals, [b]);
      expect(out.text,
          contains('Approved $b, which expires at 2026-10-17T07:00:00.000Z\n'));
    });

    test('auto_approve', () async {
      serveB(expiresAt: '2026-10-17T07:00:00.000Z');

      final out = await autoApproveB();

      expect(approvals, [b]);
      expect(
          out.text,
          contains(
              'Approval successful; $b expires at 2026-10-17T07:00:00.000Z\n'));
    });
  });

  test('at_activate approve, when the atServer does not say when B expires',
      () async {
    serveB();
    final args = AuthCliArgs().createApproveCommandParser().parse(
        ['-a', '@alice', '--${AuthCliArgs.argNameAppNameRegex}', 'wavi']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(() => auth_cli.approve(args, client),
        stdout: () => out);

    expect(approvals, [b]);
    expect(out.text, contains('Approved $b\n'));
    expect(out.text, isNot(contains('expires')));
  });

  test(
      'at_activate approve, when B is revoked before the read after the '
      'approval', () async {
    serveB(expiresAt: '2026-10-17T07:00:00.000Z', statusAfter: 'revoked');
    final args = AuthCliArgs().createApproveCommandParser().parse(
        ['-a', '@alice', '--${AuthCliArgs.argNameAppNameRegex}', 'wavi']);
    final out = _CapturedStdout();

    await IOOverrides.runZoned(() => auth_cli.approve(args, client),
        stdout: () => out);

    expect(approvals, [b]);
    expect(out.text, contains('Approved $b, but it has since been revoked\n'));
    expect(out.text, isNot(contains('expires')));
  });

  test(
      'at_activate approve, when B is revoked before the read after the '
      'approval, through auto_approve', () async {
    serveB(expiresAt: '2026-10-17T07:00:00.000Z', statusAfter: 'revoked');

    final out = await autoApproveB();

    expect(approvals, [b]);
    expect(out.text,
        contains('Approval successful, but $b has since been revoked\n'));
    expect(out.text, isNot(contains('expires')));
  });

  test('auto_approve matches --arx and --drx case-insensitively', () async {
    serveB();

    await autoApproveB(appName: 'Wavi', deviceName: 'PHONE');

    expect(approvals, [b]);
  }, timeout: const Timeout(Duration(seconds: 5)));

  group('auto_approve keeps listening past what it cannot act on', () {
    const a = 'a0a0a0a0-1a2e-43e4-93bd-378f1d366ea7';

    AtNotification announcing(String enrollmentId, String? value) =>
        AtNotification(
            'n-$enrollmentId',
            '$enrollmentId.new.enrollments.__manage@alice',
            '@alice',
            '@alice',
            DateTime.now().millisecondsSinceEpoch,
            'key',
            false)
          ..value = value;

    /// Runs `at_activate auto_approve` with a limit of one over [arriving],
    /// and hands back what it printed to stdout and to stderr.
    Future<(_CapturedStdout, _CapturedStdout)> autoApproveFrom(
        List<AtNotification> arriving) async {
      final notifications = _MockNotificationService();
      when(() => client.notificationService).thenReturn(notifications);
      when(() => notifications.subscribe(
              regex: any(named: 'regex'),
              shouldDecrypt: any(named: 'shouldDecrypt')))
          .thenAnswer((_) => Stream.fromIterable(arriving));
      final args = AuthCliArgs().createAutoApproveCommandParser().parse([
        '-a',
        '@alice',
        '--${AuthCliArgs.argNameAppNameRegex}',
        'wavi',
        '--${AuthCliArgs.argNameDeviceNameRegex}',
        'phone',
      ]);
      final out = _CapturedStdout();
      final err = _CapturedStdout();
      await IOOverrides.runZoned(() async {
        await auth_cli.autoApprove(args, client);
        await pumpEventQueue();
      }, stdout: () => out, stderr: () => err);
      return (out, err);
    }

    final request = jsonEncode({'appName': 'wavi', 'deviceName': 'phone'});

    test('A notification that is not an enrollment request is passed over',
        () async {
      serveB();

      final (out, err) = await autoApproveFrom(
          [announcing(b, 'not an enrollment request'), announcing(b, request)]);

      expect(approvals, [b]);
      expect(out.text, contains('Approved 1 requests - limit was 1 - done.'));
      expect(err.text, contains('$b.new.enrollments.__manage@alice'),
          reason: 'the notification it could not act on is reported');
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('A request whose approval fails is passed over', () async {
      serveB();

      final (out, err) = await autoApproveFrom(
          [announcing(a, request), announcing(b, request)]);

      expect(approvals, [b],
          reason: 'a is no longer awaiting approval, so only b is approved');
      expect(out.text, contains('Approved 1 requests - limit was 1 - done.'));
      expect(err.text, contains('$a.new.enrollments.__manage@alice'),
          reason: 'the failed approval is reported');
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}
