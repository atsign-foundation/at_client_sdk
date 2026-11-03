import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_client_flutter/src/widgets/pkam_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtsignFlows extends Mock implements AtsignFlows {}

class MockAtClient extends Mock implements AtClient {}

class MockPendingEnrollment extends Mock implements PendingEnrollment {}

class FakeAtClientPreference extends Fake implements AtClientPreference {}

class FakeAtClientStorage extends Fake implements AtClientStorage {}

/// PkamDialog given keys that hold only an enrollment awaiting approval waits
/// on it as ApkamActivationDialog does.
///
/// Catalogue: features/at_client_flutter/apkam_dialog.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(InMemoryAtKeysIo());
    registerFallbackValue(FakeAtClientPreference());
    registerFallbackValue(FakeAtClientStorage());
  });

  testWidgets('PkamDialog resumes a pending keychain entry', (tester) async {
    final flows = MockAtsignFlows();
    final pending = MockPendingEnrollment();
    final keys = InMemoryAtKeysIo();
    when(
      () => flows.open(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer(
      (_) => Future.error(AtEnrollmentPendingException('@alice', ['enroll-1'])),
    );
    when(
      () => flows.resumeEnrollment(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) async => pending);
    when(() => pending.enrollmentId).thenReturn('enroll-1');
    when(() => pending.progress).thenAnswer((_) => const Stream.empty());
    var opened = Completer<AtClient>();
    when(
      () => pending.client(any(), storage: any(named: 'storage')),
    ).thenAnswer((_) => opened.future);
    when(() => pending.stop()).thenAnswer((_) async {
      if (!opened.isCompleted) {
        opened.completeError(StoppedException('stopped'));
      }
    });
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
                    builder: (context) => PkamDialog(
                      atSign: '@alice',
                      keys: keys,
                      preference: AtClientPreference(),
                      storage: FakeAtClientStorage(),
                      onAuthenticationComplete: (_) {},
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

    await tester.tap(find.text('open'));
    await frames(tester);

    expect(
      find.textContaining('Waiting for approval of enrollment enroll-1'),
      findsOneWidget,
    );
    expect(find.textContaining('Authentication failed'), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await frames(tester);
    verify(() => pending.stop()).called(1);
    verifyNever(() => pending.cancel());
    expect(results, [null], reason: 'leaving keeps the request');

    opened = Completer<AtClient>();
    final client = MockAtClient();
    await tester.tap(find.text('open'));
    await frames(tester);
    opened.complete(client);
    await frames(tester);

    expect(results, [null, client]);
    final resumed = verify(
      () => flows.resumeEnrollment(
        '@alice',
        keys: captureAny(named: 'keys'),
        preference: any(named: 'preference'),
        lookUps: any(named: 'lookUps'),
      ),
    ).captured;
    expect(resumed, [
      same(keys),
      same(keys),
    ], reason: 'resumed from its own store, naming no app or device');
  });
}

/// A frame, then 400ms of them, since nothing here settles.
Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
