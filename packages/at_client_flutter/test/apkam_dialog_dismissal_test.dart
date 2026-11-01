import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_client_flutter/src/widgets/apkam_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtsignFlows extends Mock implements AtsignFlows {}

class MockAtClient extends Mock implements AtClient {}

class MockPendingEnrollment extends Mock implements PendingEnrollment {}

class FakeAtClientPreference extends Fake implements AtClientPreference {}

class FakeAtClientStorage extends Fake implements AtClientStorage {}

/// Dismissing the APKAM dialog before it hands back a client: the wait it
/// holds is cancelled, and a client opened after the dismissal is stopped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(InMemoryAtKeysIo());
    registerFallbackValue(FakeAtClientPreference());
    registerFallbackValue(FakeAtClientStorage());
  });

  late MockAtsignFlows flows;
  late MockPendingEnrollment pending;
  setUp(() {
    flows = MockAtsignFlows();
    pending = MockPendingEnrollment();
    when(() => pending.enrollmentId).thenReturn('enroll-1');
    when(() => pending.progress).thenAnswer((_) => const Stream.empty());
  });

  /// What `pending.client()` answers with. Built inside each test body, so
  /// that it completes in the widget test's zone and `pump` delivers it.
  Completer<AtClient> clientAnswers() {
    final opened = Completer<AtClient>();
    when(
      () => pending.client(any(), storage: any(named: 'storage')),
    ).thenAnswer((_) => opened.future);
    return opened;
  }

  void resumes(PendingEnrollment? request) => when(
    () => flows.resumeEnrollment(
      any(),
      app: any(named: 'app'),
      device: any(named: 'device'),
      keys: any(named: 'keys'),
      preference: any(named: 'preference'),
      lookUps: any(named: 'lookUps'),
    ),
  ).thenAnswer((_) async => request);

  /// Opens the dialog from a button and records what `showDialog` returns.
  Future<List<Object?>> open(WidgetTester tester) async {
    final results = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                results.add(
                  await showDialog<Object?>(
                    context: context,
                    builder: (context) => ApkamActivationDialog(
                      atSign: '@alice',
                      rootDomain: AtRootDomain.atsignDomain,
                      appName: 'app',
                      deviceName: 'device',
                      namespaces: const {'*': 'rw'},
                      preference: AtClientPreference(),
                      keys: InMemoryAtKeysIo(),
                      storage: FakeAtClientStorage(),
                      themeData: ThemeData(),
                      flows: flows,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // pumpAndSettle never settles here: the autofocused Pinput's cursor
    // blinks forever. Fixed frames instead.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return results;
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byType(ApkamActivationDialog),
      findsNothing,
      reason: 'the back arrow pops the dialog, and the route disposes it',
    );
  }

  group('Given the dialog is waiting for approval', () {
    testWidgets('when the user dismisses it, then the pending enrollment is '
        'cancelled: polling stops, the pending keys are removed, and no '
        'client opens', (tester) async {
      resumes(pending);
      final opened = clientAnswers();
      when(() => pending.cancel()).thenAnswer((_) async {
        opened.completeError(AtEnrollmentCancelledException('cancelled'));
      });
      final results = await open(tester);
      verify(
        () => pending.client(any(), storage: any(named: 'storage')),
      ).called(1);

      await dismiss(tester);
      await tester.pump();

      verify(() => pending.cancel()).called(1);
      expect(results, [
        null,
      ], reason: 'a dismissed dialog hands back no client');
      expect(
        tester.takeException(),
        isNull,
        reason: 'the cancelled wait ends quietly',
      );
    });

    testWidgets('when the user dismisses it while its request is still being '
        'sent, then the pending enrollment is cancelled once it arrives, and '
        'no client opens', (tester) async {
      resumes(null);
      final sent = Completer<PendingEnrollment>();
      when(
        () => flows.enroll(
          any(),
          otp: any(named: 'otp'),
          app: any(named: 'app'),
          device: any(named: 'device'),
          namespaces: any(named: 'namespaces'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          signingAlgo: any(named: 'signingAlgo'),
          keyExchangeMode: any(named: 'keyExchangeMode'),
          lookUps: any(named: 'lookUps'),
        ),
      ).thenAnswer((_) => sent.future);
      clientAnswers();
      when(() => pending.cancel()).thenAnswer((_) async {});
      final results = await open(tester);
      await tester.enterText(find.byType(EditableText), '123456');
      await tester.pump();
      expect(find.text('Waiting for approval..'), findsOneWidget);

      await dismiss(tester);
      sent.complete(pending);
      await tester.pump();

      verify(() => pending.cancel()).called(1);
      verifyNever(() => pending.client(any(), storage: any(named: 'storage')));
      expect(results, [null]);
    });
  });

  group('Given approval lands just as the dialog is dismissed', () {
    testWidgets('when pending.client() returns after the dismissal, then that '
        'client is stopped, so the next open of the atSign succeeds', (
      tester,
    ) async {
      resumes(pending);
      final opened = clientAnswers();
      when(() => pending.cancel()).thenAnswer((_) async {});
      final client = MockAtClient();
      when(() => client.stop()).thenAnswer((_) async {});
      final results = await open(tester);

      await dismiss(tester);
      opened.complete(client);
      await tester.pump();

      final stops = verify(() => client.stop()).callCount;
      expect(
        stops,
        1,
        reason:
            'nobody receives this client, and Atsign.open refuses a second '
            'live client for the atSign until it is stopped',
      );
      expect(results, [
        null,
      ], reason: 'a dismissed dialog hands back no client');
    });
  });
}
