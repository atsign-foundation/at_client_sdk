import 'dart:async';
import 'dart:io' show FileSystemException;

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

/// Leaving the APKAM dialog before it hands back a client stops the wait and
/// keeps the request; only a confirmed Cancel abandons it, and a client
/// opened after leaving is stopped.
///
/// Catalogue: features/at_client_flutter/apkam_dialog.feature
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
    when(() => pending.approved).thenReturn(false);
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

  /// `pending.stop()` ends [opened]'s wait, as the real one does.
  void stopEnds(Completer<AtClient> opened) =>
      when(() => pending.stop()).thenAnswer((_) async {
        if (!opened.isCompleted) {
          opened.completeError(StoppedException('stopped'));
        }
      });

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
    await frames(tester);
    return results;
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await frames(tester);
    expect(
      find.byType(ApkamActivationDialog),
      findsNothing,
      reason: 'the back arrow pops the dialog, and the route disposes it',
    );
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await frames(tester);
  }

  group('Given the dialog waiting for approval', () {
    testWidgets('Leaving the waiting screen keeps the request', (tester) async {
      resumes(pending);
      final opened = clientAnswers();
      stopEnds(opened);
      final results = await open(tester);
      verify(
        () => pending.client(any(), storage: any(named: 'storage')),
      ).called(1);

      await leave(tester);
      await tester.pump();

      verify(() => pending.stop()).called(1);
      verifyNever(() => pending.cancel());
      expect(results, [
        null,
      ], reason: 'a dialog the user left hands back no client');
      expect(
        tester.takeException(),
        isNull,
        reason: 'the stopped wait ends quietly',
      );
    });

    testWidgets('Leaving while the request is still being sent', (
      tester,
    ) async {
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
      when(() => pending.stop()).thenAnswer((_) async {});
      final results = await open(tester);
      await tester.enterText(find.byType(EditableText), '123456');
      await tester.pump();
      expect(find.text('Waiting for approval..'), findsOneWidget);

      await leave(tester);
      sent.complete(pending);
      await tester.pump();

      verify(() => pending.stop()).called(1);
      verifyNever(() => pending.cancel());
      verifyNever(() => pending.client(any(), storage: any(named: 'storage')));
      expect(results, [null]);
    });

    testWidgets('Cancel asks first', (tester) async {
      resumes(pending);
      stopEnds(clientAnswers());
      await open(tester);

      await tapText(tester, 'Cancel');

      expect(
        find.textContaining('This abandons enrollment enroll-1 of @alice'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Trying again needs a new OTP from another '
          'enrollment of @alice',
        ),
        findsOneWidget,
      );
      verifyNever(() => pending.cancel());
      verifyNever(() => pending.stop());
      expect(find.byType(ApkamActivationDialog), findsOneWidget);
    });

    testWidgets('A confirmed Cancel abandons', (tester) async {
      resumes(pending);
      final opened = clientAnswers();
      stopEnds(opened);
      when(() => pending.cancel()).thenAnswer((_) async {
        opened.completeError(AtEnrollmentCancelledException('cancelled'));
      });
      final results = await open(tester);

      await tapText(tester, 'Cancel');
      await tapText(tester, 'Abandon');

      verify(() => pending.cancel()).called(1);
      expect(
        find.text(
          'Enrollment enroll-1 abandoned. Ask the manager of @alice to deny '
          'it.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ApkamActivationDialog), findsNothing);
      expect(results, [null]);
      expect(
        find.textContaining('Activation failed'),
        findsNothing,
        reason: 'abandoning is not a failure',
      );
    });

    testWidgets('A confirmed Cancel after the approval was written lets the '
        'approval stand', (tester) async {
      resumes(pending);
      when(() => pending.approved).thenReturn(true);
      when(() => pending.stop()).thenAnswer((_) async {});
      final ended = Completer<void>();
      final waitEnded = Completer<void>();
      final releaseFirstStop = Completer<void>();
      final first = MockAtClient();
      var firstLive = true;
      when(() => first.stop()).thenAnswer((_) async {
        await releaseFirstStop.future;
        firstLive = false;
      });
      // As client() does: the client opened on the written approval is live
      // until the ended wait stops it, and then the wait throws.
      when(
        () => pending.client(any(), storage: any(named: 'storage')),
      ).thenAnswer((_) async {
        try {
          await ended.future;
          await first.stop();
          throw AtEnrollmentCancelledException('cancelled after the approval');
        } finally {
          waitEnded.complete();
        }
      });
      // As cancel() does: it ends the wait and returns once client() has
      // ended, having stopped the client it opened.
      when(() => pending.cancel()).thenAnswer((_) async {
        if (!ended.isCompleted) ended.complete();
        await waitEnded.future;
      });
      final second = MockAtClient();
      final liveAtSecondOpen = <bool>[];
      when(
        () => flows.open(
          any(),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          storage: any(named: 'storage'),
          lookUps: any(named: 'lookUps'),
        ),
      ).thenAnswer((_) async {
        liveAtSecondOpen.add(firstLive);
        return second;
      });
      final results = await open(tester);

      await tapText(tester, 'Cancel');
      await tapText(tester, 'Abandon');

      verify(() => pending.cancel()).called(1);
      expect(
        liveAtSecondOpen,
        isEmpty,
        reason:
            'cancel() returns only once the client its wait opened has '
            'stopped, as this double models PendingEnrollment doing, and the '
            'dialog opens the approved keys only after cancel() returns',
      );

      releaseFirstStop.complete();
      await frames(tester);

      expect(
        find.text(
          'The approval of enrollment enroll-1 landed before the Cancel took '
          'effect, so it stands.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('deny'), findsNothing);
      expect(find.textContaining('revoke'), findsNothing);
      expect(liveAtSecondOpen, [false]);
      expect(results, [
        second,
      ], reason: 'the dialog returns the client opened on the approved keys');
    });

    testWidgets('A declined Cancel changes nothing', (tester) async {
      resumes(pending);
      final opened = clientAnswers();
      stopEnds(opened);
      final client = MockAtClient();
      final results = await open(tester);

      await tapText(tester, 'Cancel');
      await tapText(tester, 'Keep waiting');
      opened.complete(client);
      await frames(tester);

      verifyNever(() => pending.cancel());
      expect(results, [
        client,
      ], reason: 'the wait went on and handed back the approved client');
    });

    testWidgets('A confirmed Cancel that cannot remove the keys says so, and '
        'the request is kept', (tester) async {
      resumes(pending);
      final opened = clientAnswers();
      stopEnds(opened);
      when(() => pending.cancel()).thenAnswer((_) async {
        if (!opened.isCompleted) {
          opened.completeError(AtEnrollmentCancelledException('cancelled'));
        }
        throw const FileSystemException('the keyfile lock is held');
      });
      final results = await open(tester);

      await tapText(tester, 'Cancel');
      await tapText(tester, 'Abandon');

      expect(
        find.textContaining('Could not abandon enrollment enroll-1'),
        findsOneWidget,
      );
      expect(find.byType(ApkamActivationDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(results, isEmpty);

      await tapText(tester, 'Cancel');

      expect(
        find.text('Abandon'),
        findsNothing,
        reason: 'the user already confirmed; Cancel again retries',
      );
      verify(() => pending.cancel()).called(2);

      await leave(tester);
      await tester.pump();

      verifyNever(() => pending.stop());
      expect(results, [null]);
      resumes(pending);
      clientAnswers();
      await tester.tap(find.text('open'));
      await frames(tester);
      verify(
        () => pending.client(any(), storage: any(named: 'storage')),
      ).called(2);
    });

    testWidgets('An approval landing while Cancel is being confirmed closes '
        'the confirmation and returns the client', (tester) async {
      resumes(pending);
      final opened = clientAnswers();
      stopEnds(opened);
      final client = MockAtClient();
      final results = await open(tester);
      await tapText(tester, 'Cancel');

      opened.complete(client);
      await frames(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ApkamActivationDialog), findsNothing);
      verifyNever(() => pending.cancel());
      expect(results, [client]);
      expect(tester.takeException(), isNull);
    });
  });

  group('Given approval lands just as the dialog is dismissed', () {
    testWidgets('when pending.client() returns after the dismissal, then that '
        'client is stopped, so the next open of the atSign succeeds', (
      tester,
    ) async {
      resumes(pending);
      final opened = clientAnswers();
      when(() => pending.stop()).thenAnswer((_) async {});
      final client = MockAtClient();
      when(() => client.stop()).thenAnswer((_) async {});
      final results = await open(tester);

      await leave(tester);
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

/// A frame, then 400ms of them, since nothing here settles.
Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
