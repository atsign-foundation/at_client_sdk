import 'dart:async';
import 'dart:io' show FileSystemException;

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

/// Records each route the navigator pops.
class _PopRecorder extends NavigatorObserver {
  final popped = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
}

/// PkamDialog, waiting on the enrollment it resumed from a keychain entry,
/// offers ApkamActivationDialog's Cancel: only a confirmed Cancel abandons
/// the request.
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
  late _PopRecorder pops;

  /// What each `flows.open` after the first, which finds only the pending
  /// enrollment, answers with.
  late Future<AtClient> Function() reopens;
  setUp(() {
    pops = _PopRecorder();
    flows = MockAtsignFlows();
    pending = MockPendingEnrollment();
    when(() => pending.enrollmentId).thenReturn('enroll-1');
    when(() => pending.progress).thenAnswer((_) => const Stream.empty());
    when(() => pending.approved).thenReturn(false);
    reopens = () => Future.error(StateError('no second open expected'));
    var opens = 0;
    when(
      () => flows.open(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) {
      if (opens++ == 0) {
        return Future.error(
          AtEnrollmentPendingException('@alice', ['enroll-1']),
        );
      }
      return reopens();
    });
    when(
      () => flows.resumeEnrollment(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) async => pending);
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
  void stopEnds(Completer<AtClient> opened) {
    when(() => pending.stop()).thenAnswer((_) async {
      if (!opened.isCompleted) {
        opened.completeError(StoppedException('stopped'));
      }
    });
  }

  /// Opens PkamDialog on a keychain entry holding only `pending`, from a
  /// button, and records what `showDialog` returns and what
  /// `onAuthenticationComplete` is handed.
  Future<(List<Object?>, List<AtClient>)> open(WidgetTester tester) async {
    final results = <Object?>[];
    final completed = <AtClient>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [pops],
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                results.add(
                  await showDialog<Object?>(
                    context: context,
                    builder: (context) => PkamDialog(
                      atSign: '@alice',
                      keys: InMemoryAtKeysIo(),
                      preference: AtClientPreference(),
                      storage: FakeAtClientStorage(),
                      onAuthenticationComplete: completed.add,
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
      reason: 'PkamDialog waits on the enrollment it resumed',
    );
    return (results, completed);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await frames(tester);
  }

  void noFailureShown() => expect(
    find.textContaining('Something went wrong'),
    findsNothing,
    reason: 'abandoning is not a failure',
  );

  testWidgets("PkamDialog's Cancel asks first", (tester) async {
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
    expect(find.byType(PkamDialog), findsOneWidget);
  });

  testWidgets('A confirmed Cancel in PkamDialog abandons', (tester) async {
    final opened = clientAnswers();
    stopEnds(opened);
    when(() => pending.cancel()).thenAnswer((_) async {
      opened.completeError(AtEnrollmentCancelledException('cancelled'));
    });
    final (results, completed) = await open(tester);

    await tapText(tester, 'Cancel');
    await tapText(tester, 'Abandon');

    verify(() => pending.cancel()).called(1);
    noFailureShown();
    expect(
      find.text(
        'Enrollment enroll-1 abandoned. Ask the manager of @alice to deny '
        'it.',
      ),
      findsOneWidget,
    );
    expect(find.byType(PkamDialog), findsNothing);
    expect(results, [null]);
    expect(completed, isEmpty);

    for (var tick = 0; tick < 10; tick++) {
      await tester.pump(const Duration(seconds: 1));
      noFailureShown();
    }
  });

  testWidgets('A confirmed Cancel in PkamDialog after the approval was '
      'written lets the approval stand', (tester) async {
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
    reopens = () async {
      liveAtSecondOpen.add(firstLive);
      return second;
    };
    final (results, completed) = await open(tester);

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
    expect(liveAtSecondOpen, [false]);
    expect(results, [
      second,
    ], reason: 'the dialog returns the client opened on the approved keys');
    expect(completed, [
      second,
    ], reason: 'onAuthenticationComplete is handed the client returned');
  });

  testWidgets('A declined Cancel in PkamDialog changes nothing', (
    tester,
  ) async {
    final opened = clientAnswers();
    stopEnds(opened);
    final client = MockAtClient();
    final (results, _) = await open(tester);

    await tapText(tester, 'Cancel');
    await tapText(tester, 'Keep waiting');
    expect(
      find.textContaining('Waiting for approval of enrollment enroll-1'),
      findsOneWidget,
    );
    opened.complete(client);
    await frames(tester);

    verifyNever(() => pending.cancel());
    expect(results, [
      client,
    ], reason: 'the wait went on and handed back the approved client');
  });

  testWidgets('A confirmed Cancel in PkamDialog that cannot remove the keys '
      'says so, and the request is kept', (tester) async {
    final opened = clientAnswers();
    stopEnds(opened);
    when(() => pending.cancel()).thenAnswer((_) async {
      if (!opened.isCompleted) {
        opened.completeError(AtEnrollmentCancelledException('cancelled'));
      }
      throw const FileSystemException('the keyfile lock is held');
    });
    final (results, _) = await open(tester);

    await tapText(tester, 'Cancel');
    await tapText(tester, 'Abandon');

    noFailureShown();
    expect(
      find.text(
        'Could not abandon enrollment enroll-1: its keys are still in the '
        'key store. Choose Cancel to try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Waiting for approval'),
      findsNothing,
      reason: 'its wait has ended',
    );
    expect(find.byType(PkamDialog), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(results, isEmpty);

    await tapText(tester, 'Cancel');

    expect(
      find.text('Abandon'),
      findsNothing,
      reason: 'the user already confirmed; Cancel again retries',
    );
    verify(() => pending.cancel()).called(2);

    await tester.tapAt(const Offset(4, 4));
    await frames(tester);
    verifyNever(() => pending.stop());
    expect(results, [null]);
  });

  testWidgets('An approval landing while PkamDialog\'s Cancel is being '
      'confirmed closes the confirmation and returns the client', (
    tester,
  ) async {
    final opened = clientAnswers();
    stopEnds(opened);
    final client = MockAtClient();
    final (results, _) = await open(tester);
    await tapText(tester, 'Cancel');
    expect(find.byType(AlertDialog), findsOneWidget);

    opened.complete(client);
    await frames(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PkamDialog), findsNothing);
    verifyNever(() => pending.cancel());
    expect(results, [client]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PkamDialog says so when another wait has cancelled the '
      'request it waits on', (tester) async {
    final opened = clientAnswers();
    stopEnds(opened);
    final (results, completed) = await open(tester);
    expect(find.text('Cancel'), findsOneWidget, reason: 'it is waiting');

    opened.completeError(AtEnrollmentCancelledException(cancelledElsewhere));
    await frames(tester);

    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(
          "the atSign's manager can revoke enrollment",
        ),
      ),
      findsOneWidget,
      reason: 'the failure is shown',
    );
    expect(find.byType(PkamDialog), findsNothing);
    expect(results, [null], reason: 'the dialog closes with no client');
    expect(completed, isEmpty);
    verifyNever(() => pending.cancel());
  });

  testWidgets('A failure while PkamDialog\'s Cancel is being confirmed closes '
      'the confirmation and the dialog', (tester) async {
    final opened = clientAnswers();
    stopEnds(opened);
    final (results, completed) = await open(tester);
    await tapText(tester, 'Cancel');
    expect(find.byType(AlertDialog), findsOneWidget);

    opened.completeError(
      AtEnrollmentDeniedException('enrollment enroll-1 of @alice was denied'),
    );
    await frames(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('enroll-1 of @alice was denied'),
      ),
      findsOneWidget,
      reason: 'the failure is shown',
    );
    expect(
      find.byType(PkamDialog),
      findsNothing,
      reason: 'the failure closes the dialog, not only the confirmation',
    );
    expect(results, [null], reason: 'the dialog closes with no client');
    expect(completed, isEmpty);
    verifyNever(() => pending.cancel());
  });

  testWidgets('A failure ending PkamDialog\'s wait as its confirmed Cancel '
      'runs closes the dialog once', (tester) async {
    final opened = clientAnswers();
    stopEnds(opened);
    // The Cancel's ending runs first and the denial's after it.
    when(() => pending.cancel()).thenAnswer((_) async {
      Timer(const Duration(milliseconds: 1), () {
        opened.completeError(
          AtEnrollmentDeniedException(
            'enrollment enroll-1 of @alice was denied',
          ),
        );
      });
    });
    final (results, completed) = await open(tester);

    await tapText(tester, 'Cancel');
    await tapText(tester, 'Abandon');

    expect(find.byType(PkamDialog), findsNothing);
    expect(
      pops.popped.whereType<PageRoute<dynamic>>(),
      isEmpty,
      reason: 'only the dialog closes, not the screen beneath it',
    );
    expect(results, [null], reason: 'the dialog closes with no client');
    expect(completed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Given PkamDialog waiting, when the approval lands as the '
      'dialog closes, then its client is stopped and nothing beneath the '
      'dialog is popped', (tester) async {
    final opened = clientAnswers();
    when(() => pending.stop()).thenAnswer((_) async {});
    final client = MockAtClient();
    when(() => client.stop()).thenAnswer((_) async {});
    final (results, completed) = await open(tester);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    opened.complete(client);
    await frames(tester);

    verify(() => client.stop()).called(1);
    expect(pops.popped.whereType<PageRoute<dynamic>>(), isEmpty);
    expect(results, [null]);
    expect(completed, isEmpty);
  });
}

/// What `PendingEnrollment` throws when another wait for the same request
/// cancelled it before the approval was filed.
const cancelledElsewhere =
    "the atSign's manager can revoke enrollment \"enroll-1\" of @alice: it "
    'was approved after its pending keys left its key store, so nothing is '
    'filed';

/// A frame, then 400ms of them, since nothing here settles.
Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
