/// The approval list's last hop tells the truth, and every read goes through
/// the client the widget was given.
///
/// A conveyance refusal means the approval already went through, so the row
/// is no longer pending and calling it a failure would invite a retry; a
/// pq-mode request wraps no symmetric key; and a client the app owns is used
/// without reaching AtClientManager.
library;

// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show AtEnrollmentResponse, EnrollmentRequestDecision;
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtClient extends Mock implements AtClient {}

class MockEnrollmentService extends Mock implements EnrollmentService {}

class MockNotificationService extends Mock implements NotificationService {}

class FakeEnrollmentRequestDecision extends Fake
    implements EnrollmentRequestDecision {}

class FakeListParams extends Fake implements EnrollmentListRequestParam {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const atSign = '@alice';
  const enrollmentId = 'list-eid-1';

  late MockAtClient atClient;
  late MockEnrollmentService service;
  late MockNotificationService notifications;

  /// A pq-mode pending request: the enrollee wrapped no symmetric key.
  AtNotification announcement() =>
      AtNotification(
          'n-1',
          '$enrollmentId.new.enrollments.__manage$atSign',
          atSign,
          atSign,
          0,
          'key',
          false,
        )
        ..value = jsonEncode({
          'appName': 'buzz',
          'deviceName': 'pixel',
          'namespace': <String, String>{},
        });

  Enrollment pendingRecord() => Enrollment()
    ..enrollmentId = enrollmentId
    ..appName = 'buzz'
    ..deviceName = 'pixel'
    ..status = 'pending'
    ..namespace = <String, String>{};

  setUpAll(() {
    registerFallbackValue(FakeEnrollmentRequestDecision());
    registerFallbackValue(FakeListParams());
  });

  setUp(() {
    // The reset leaves AtClientManager.atClient throwing, so any client read
    // that does not go through the injected client fails the test.
    AtClientManager.getInstance().reset();

    atClient = MockAtClient();
    service = MockEnrollmentService();
    notifications = MockNotificationService();

    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentService).thenReturn(service);
    when(() => atClient.notificationService).thenReturn(notifications);
    when(
      () => notifications.subscribe(
        regex: any(named: 'regex'),
        shouldDecrypt: any(named: 'shouldDecrypt'),
      ),
    ).thenAnswer((_) => Stream.value(announcement()));
    // The roster holds the request, which is what approve() reads the wrapped
    // key off; the initial fetch and the stream both hand it to the widget,
    // which de-duplicates.
    when(
      () => service.fetchEnrollmentRequests(
        enrollmentListParams: any(named: 'enrollmentListParams'),
      ),
    ).thenAnswer((_) async => [pendingRecord()]);
  });

  tearDown(() => AtClientManager.getInstance().reset());

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EnrollmentRequestList(atClient: atClient)),
      ),
    );
    await tester.pump();
  }

  testWidgets('a conveyance refusal shows the truth and clears the row', (
    tester,
  ) async {
    final refusal = EnrollmentConveyanceException(
      'Enrollment $enrollmentId is approved, but the key package it '
      'advertised does not verify against its _apsk, so no secrets were '
      'shared with it and it will be unable to decrypt anything. Revoke it '
      'unless this is understood.',
      response: AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
      keyPackageStatus: KeyPackageStatus.rejected,
    );
    when(() => service.approve(any())).thenThrow(refusal);

    await pumpList(tester);
    expect(find.text('Approve'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Revoke it unless this is understood'),
      findsOneWidget,
      reason:
          'the refusal\'s own prose is the truth: approved, cannot '
          'decrypt, consider revoking',
    );
    expect(
      find.textContaining('Failed to approve'),
      findsNothing,
      reason:
          'the approval did not fail; saying so invites a retry of an '
          'approval that already went through',
    );
    expect(
      find.text('No pending enrollment requests'),
      findsOneWidget,
      reason: 'the request is no longer pending either way',
    );
  });

  testWidgets('a pq-mode request that wrapped no key is approvable', (
    tester,
  ) async {
    when(() => service.approve(any())).thenAnswer(
      (_) async =>
          AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
    );

    await pumpList(tester);
    await tester.tap(find.text('Approve'));
    await tester.pump();

    final decision =
        verify(() => service.approve(captureAny())).captured.single
            as EnrollmentRequestDecision;
    expect(decision.enrollmentId, enrollmentId);
    expect(
      decision.encryptedAPKAMSymmetricKey,
      isEmpty,
      reason:
          'the enrollee wrapped no key — the approver mints one, and '
          'empty is that signal; a null-bang here crashed every pq-mode '
          'approval before the service was even called',
    );
    // Let the feedback overlay's auto-dismiss run down before teardown.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a denial goes through the client the widget was given', (
    tester,
  ) async {
    when(() => service.deny(any())).thenAnswer(
      (_) async => AtEnrollmentResponse(enrollmentId, EnrollmentStatus.denied),
    );

    await pumpList(tester);
    await tester.tap(find.text('Reject'));
    await tester.pump();

    final decision =
        verify(() => service.deny(captureAny())).captured.single
            as EnrollmentRequestDecision;
    expect(decision.enrollmentId, enrollmentId);
    expect(find.text('No pending enrollment requests'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('works against an app-owned client, without AtClientManager', (
    tester,
  ) async {
    when(
      () => notifications.subscribe(
        regex: any(named: 'regex'),
        shouldDecrypt: any(named: 'shouldDecrypt'),
      ),
    ).thenAnswer((_) => const Stream<AtNotification>.empty());
    when(
      () => service.fetchEnrollmentRequests(
        enrollmentListParams: any(named: 'enrollmentListParams'),
      ),
    ).thenAnswer((_) async => []);

    await pumpList(tester);
    await tester.pumpAndSettle();

    // AtClientManager was reset, so its atClient getter throws. The widget
    // catches everything and renders the message rather than crashing, which
    // is what makes this a trap - so assert on the absence of that text.
    expect(
      find.textContaining('No atClient yet'),
      findsNothing,
      reason:
          'every client read goes through the client the app supplied, so '
          'an app that opened its own client can use this widget - reaching '
          'AtClientManager here would throw for exactly the apps the '
          'lifecycle verbs exist to serve',
    );
    expect(find.text('No pending enrollment requests'), findsOneWidget);
  });
}
