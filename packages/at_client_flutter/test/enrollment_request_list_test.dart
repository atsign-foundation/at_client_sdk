import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/services/enrollment_service.dart';
import 'package:at_client_flutter/src/widgets/authorisation/containers/enrollment_request_list.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterEnrollmentService extends Mock
    implements FlutterEnrollmentService {}

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookUp extends Mock implements AtLookUp {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => registerFallbackValue(MockAtLookUp()));

  setUp(() => AtClientManager.getInstance().reset());
  tearDown(() => AtClientManager.getInstance().reset());

  testWidgets('works against an app-owned client, without AtClientManager', (
    tester,
  ) async {
    final service = MockFlutterEnrollmentService();
    final atClient = MockAtClient();
    final remoteSecondary = MockRemoteSecondary();

    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(MockAtLookUp());
    when(() => atClient.getCurrentAtSign()).thenReturn('@appowned');
    when(() => service.atClient).thenReturn(atClient);
    when(
      () => service.getEnrollments(statusFilters: any(named: 'statusFilters')),
    ).thenAnswer((_) => const Stream<EnrollmentServerResponse>.empty());
    when(
      () => service.list(
        any(),
        any(),
        drx: any(named: 'drx'),
        arx: any(named: 'arx'),
      ),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EnrollmentRequestList(enrollmentService: service)),
      ),
    );
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
