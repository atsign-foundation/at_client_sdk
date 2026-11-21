import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_client_flutter/src/widgets/apkam_dialog.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtsignFlows extends Mock implements AtsignFlows {}

class MockAtClient extends Mock implements AtClient {}

class MockPendingEnrollment extends Mock implements PendingEnrollment {}

class FakeAtClientPreference extends Fake implements AtClientPreference {}

class FakeAtClientStorage extends Fake implements AtClientStorage {}

/// Every record logged, as its level's name and its message.
class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) => records.add((
    level: '${record.level.name}',
    message: '${record.message}',
  ));

  /// Makes this the handler every logger built from now on binds, until the
  /// test ends.
  void installUntilTearDown() {
    final handler = AtSignLogger.defaultLoggingHandler;
    final level = AtSignLogger.root_level;
    AtSignLogger.defaultLoggingHandler = this;
    AtSignLogger.root_level = 'info';
    addTearDown(() {
      AtSignLogger.defaultLoggingHandler = handler;
      AtSignLogger.root_level = level;
    });
  }
}

/// A request filed in a key store under [enrollmentId] by [app] on [device],
/// which has not been decided.
MockPendingEnrollment filed(
  String enrollmentId, {
  required String app,
  required String device,
}) {
  final request = MockPendingEnrollment();
  when(() => request.enrollmentId).thenReturn(enrollmentId);
  when(() => request.app).thenReturn(app);
  when(() => request.device).thenReturn(device);
  when(() => request.progress).thenAnswer((_) => const Stream.empty());
  when(() => request.approved).thenReturn(false);
  return request;
}

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
    pending = filed('enroll-1', app: 'app', device: 'device');
  });

  /// What `request.client()`, `pending`'s by default, answers with. Built
  /// inside each test body, so that it completes in the widget test's zone
  /// and `pump` delivers it.
  Completer<AtClient> clientAnswers([PendingEnrollment? request]) {
    final waiting = request ?? pending;
    final opened = Completer<AtClient>();
    when(
      () => waiting.client(any(), storage: any(named: 'storage')),
    ).thenAnswer((_) => opened.future);
    return opened;
  }

  /// `request.stop()`, `pending`'s by default, ends [opened]'s wait, as the
  /// real one does.
  void stopEnds(Completer<AtClient> opened, [PendingEnrollment? request]) {
    final waiting = request ?? pending;
    when(() => waiting.stop()).thenAnswer((_) async {
      if (!opened.isCompleted) {
        opened.completeError(StoppedException('stopped'));
      }
    });
  }

  /// `flows.resumeEnrollment` answers as `Atsign.resumeEnrollment` does over
  /// a key store holding [requests]: each name given narrows the search, and
  /// more than one request left throws.
  void holding(List<PendingEnrollment> requests) =>
      when(
        () => flows.resumeEnrollment(
          any(),
          app: any(named: 'app'),
          device: any(named: 'device'),
          keys: any(named: 'keys'),
          preference: any(named: 'preference'),
          lookUps: any(named: 'lookUps'),
        ),
      ).thenAnswer((invocation) async {
        final app = invocation.namedArguments[#app] as String?;
        final device = invocation.namedArguments[#device] as String?;
        final matching = [
          for (final request in requests)
            if ((app == null || request.app == app) &&
                (device == null || request.device == device))
              request,
        ];
        if (matching.length > 1) {
          throw AtEnrollmentPendingException.several('@alice', [
            for (final request in matching) request.enrollmentId,
          ]);
        }
        return matching.isEmpty ? null : matching.single;
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

  /// Opens the dialog for [appName] on [deviceName] from a button and records
  /// what `showDialog` returns.
  Future<List<Object?>> open(
    WidgetTester tester, {
    String appName = 'app',
    String deviceName = 'device',
  }) async {
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
                      appName: appName,
                      deviceName: deviceName,
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
        find.textContaining('Something went wrong'),
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

  void neverEnrolls() => verifyNever(
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
  );

  for (final (app, device) in const [
    ('wavi', 'phone'),
    ('wavi-old', 'tablet'),
  ]) {
    testWidgets('The enrollment dialog adopts the request its store holds '
        'under another app or device name', (tester) async {
      final logs = _RecordedLogs()..installUntilTearDown();
      final request = filed('enroll-1', app: 'wavi-old', device: 'phone');
      holding([request]);
      final opened = clientAnswers(request);
      stopEnds(opened, request);
      final client = MockAtClient();
      final results = await open(tester, appName: app, deviceName: device);

      expect(
        find.text('Resuming enrollment enroll-1, filed as wavi-old on phone..'),
        findsOneWidget,
        reason: 'opened as $app on $device',
      );
      expect(find.text('Cancel'), findsOneWidget);
      neverEnrolls();
      final warnings = [
        for (final record in logs.records)
          if (record.level == 'WARNING') record.message,
      ];
      expect(
        warnings,
        [
          allOf(
            contains('enroll-1'),
            contains('@alice'),
            contains('by app "wavi-old" on device "phone"'),
            contains('for app $app on device $device'),
          ),
        ],
        reason:
            'opened as $app on $device: one warning, naming the request, '
            'the names it was filed under and the names of this dialog',
      );

      opened.complete(client);
      await frames(tester);

      expect(
        results,
        [client],
        reason:
            'opened as $app on $device: the adopted request\'s approval '
            'opens the client here',
      );
    });
  }

  group('Given a store whose pending enrollment records no app and no '
      'device', () {
    testWidgets('when the enrollment dialog opens @alice for app wavi, then '
        'it resumes that enrollment saying nothing of names', (tester) async {
      final logs = _RecordedLogs()..installUntilTearDown();
      final request = filed('enroll-1', app: '', device: '');
      holding([request]);
      stopEnds(clientAnswers(request), request);
      await open(tester, appName: 'wavi', deviceName: 'phone');

      expect(find.text('Resuming enrollment enroll-1..'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      neverEnrolls();
      final warnings = [
        for (final record in logs.records)
          if (record.level == 'WARNING') record.message,
      ];
      expect(warnings, [
        'Adopting enrollment "enroll-1" of @alice for app wavi on device phone',
      ], reason: 'one warning, naming the request and this dialog alone');
    });
  });

  testWidgets('The enrollment dialog waits on its own request when its store '
      'holds several', (tester) async {
    final phone = filed('enroll-phone', app: 'app', device: 'phone');
    final oldPhone = filed('enroll-old-phone', app: 'app', device: 'old-phone');
    holding([phone, oldPhone]);
    stopEnds(clientAnswers(phone), phone);
    await open(tester, deviceName: 'phone');

    expect(find.text('Resuming enrollment enroll-phone..'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    neverEnrolls();
    verifyNever(() => oldPhone.client(any(), storage: any(named: 'storage')));
  });

  testWidgets('The enrollment dialog resumes this app\'s request from another '
      'device before another app\'s', (tester) async {
    final wavi = filed('enroll-wavi', app: 'wavi', device: 'old-phone');
    final buzz = filed('enroll-buzz', app: 'buzz', device: 'phone');
    holding([wavi, buzz]);
    stopEnds(clientAnswers(wavi), wavi);
    await open(tester, appName: 'wavi', deviceName: 'new-phone');

    expect(
      find.text(
        'Resuming enrollment enroll-wavi, filed as wavi on old-phone..',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    neverEnrolls();
    verifyNever(() => buzz.client(any(), storage: any(named: 'storage')));
  });

  testWidgets('The enrollment dialog shows a recorded app name with its '
      'control characters escaped', (tester) async {
    final request = filed('enroll-1', app: 'wa\u001bvi', device: 'phone');
    holding([request]);
    stopEnds(clientAnswers(request), request);
    await open(tester, appName: 'wavi', deviceName: 'phone');

    expect(
      find.text(
        r'Resuming enrollment enroll-1, filed as wa\u001bvi on phone..',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets("The enrollment dialog's adoption warning names the recorded "
      'app quoted and escaped', (tester) async {
    final logs = _RecordedLogs()..installUntilTearDown();
    final request = filed('enroll-1', app: 'wa\u001bvi', device: 'phone');
    holding([request]);
    stopEnds(clientAnswers(request), request);
    await open(tester, appName: 'wavi', deviceName: 'phone');

    final warnings = [
      for (final record in logs.records)
        if (record.level == 'WARNING') record.message,
    ];
    expect(warnings, [contains(r'by app "wa\u001bvi"')]);
  });

  testWidgets("The enrollment dialog's adoption warning escapes a double "
      'quote inside the recorded app name', (tester) async {
    final logs = _RecordedLogs()..installUntilTearDown();
    final request = filed('enroll-1', app: 'wa"vi', device: 'phone');
    holding([request]);
    stopEnds(clientAnswers(request), request);
    await open(tester, appName: 'wavi', deviceName: 'phone');

    final warnings = [
      for (final record in logs.records)
        if (record.level == 'WARNING') record.message,
    ];
    expect(warnings, [
      contains(r'by app "wa\"vi"'),
    ], reason: 'the filed app in double quotes, the quote inside it escaped');
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
