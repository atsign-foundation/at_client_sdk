/// The approval list's last hop tells the truth, and every client read goes
/// through the service it was given.
///
/// A post-approval conveyance refusal means the enrollment is live and
/// cannot decrypt — reporting it as `Failed to approve` invites a retry of
/// an approval that already went through, and leaving the row listed says
/// the request is still pending when it is not. And a pq-mode request wraps
/// no symmetric key at all, so the row's approve action must not demand one.
/// An injected service belongs to the caller: the widget neither disposes it
/// nor reaches past it to [AtClientManager], so an app that owns its own
/// client can use this widget.
library;

// The conveyance surface is deliberately marked @experimental and will be
// reshaped as the group surface matures.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterEnrollmentService extends Mock
    implements FlutterEnrollmentService {}

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookUp extends Mock implements AtLookUp {}

class FakeEnrollmentRequestDecision extends Fake
    implements EnrollmentRequestDecision {}

class FakeAtLookUp extends Fake implements AtLookUp {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const atSign = '@alice';
  const enrollmentId = 'list-eid-1';

  late MockFlutterEnrollmentService service;
  late MockAtClient atClient;
  late MockRemoteSecondary secondary;
  late MockAtLookUp atLookUp;

  /// A pq-mode pending request: the enrollee wrapped no symmetric key.
  final request = ServerEnrollmentRequest(
    enrollmentId: enrollmentId,
    appName: 'buzz',
    deviceName: 'pixel',
    status: EnrollmentStatus.pending,
    namespacePermissions: const [],
  );

  setUpAll(() {
    registerFallbackValue(FakeEnrollmentRequestDecision());
    registerFallbackValue(FakeAtLookUp());
    registerFallbackValue(<EnrollmentStatus>[]);
  });

  setUp(() {
    // Nothing here may reach the manager: every client read is expected to
    // go through the injected service.
    AtClientManager.getInstance().reset();

    service = MockFlutterEnrollmentService();
    atClient = MockAtClient();
    secondary = MockRemoteSecondary();
    atLookUp = MockAtLookUp();

    when(
      () => service.getEnrollments(statusFilters: any(named: 'statusFilters')),
    ).thenAnswer((_) => Stream.value(request));
    // The initial fetch; the stream above already delivers the request and
    // the widget de-duplicates, so empty keeps the fixture single-sourced.
    when(
      () => service.list(
        any(),
        any(),
        drx: any(named: 'drx'),
        arx: any(named: 'arx'),
      ),
    ).thenAnswer((_) async => []);
    when(() => service.atClient).thenReturn(atClient);
    when(() => service.dispose()).thenAnswer((_) async {});
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(atLookUp);
  });

  tearDown(() => AtClientManager.getInstance().reset());

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EnrollmentRequestList(enrollmentService: service)),
      ),
    );
    await tester.pump(); // the stream delivers the pending request
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
    when(() => service.approve(any(), any())).thenThrow(refusal);

    await pumpList(tester);
    expect(find.text('Approve'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pump(); // the handler runs
    await tester.pump(); // the snackbar animates in

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
    when(() => service.approve(any(), any())).thenAnswer(
      (_) async =>
          AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
    );

    await pumpList(tester);
    await tester.tap(find.text('Approve'));
    await tester.pump();

    final decision =
        verify(() => service.approve(captureAny(), any())).captured.single
            as EnrollmentRequestDecision;
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

  testWidgets('an injected service outlives the widget', (tester) async {
    await pumpList(tester);
    // Route away, disposing the widget.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    verifyNever(() => service.dispose());
  });

  testWidgets('works against an app-owned client, without AtClientManager', (
    tester,
  ) async {
    when(
      () => service.getEnrollments(statusFilters: any(named: 'statusFilters')),
    ).thenAnswer((_) => const Stream<EnrollmentServerResponse>.empty());

    await pumpList(tester);
    await tester.pumpAndSettle();

    // AtClientManager was reset, so its atClient getter throws. The widget
    // catches everything and renders the message rather than crashing, which
    // is what makes this a trap - so assert on the absence of that text.
    expect(
      find.textContaining('No atClient yet'),
      findsNothing,
      reason:
          'every client read goes through the service the app supplied, '
          'so an app that built its client with AuthService.createClient '
          'can use this widget - reaching AtClientManager here would throw '
          'for exactly the apps the new factory exists to serve',
    );
    verify(() => service.atClient).called(greaterThan(0));
  });
}
