/// The approval list's last hop tells the truth, and every read goes through
/// the client the widget was given.
///
/// A conveyance refusal means the approval already went through, so the row
/// is no longer pending and calling it a failure would invite a retry; a
/// pq-mode request wraps no symmetric key; and a client the app owns is used
/// without reaching AtClientManager.
library;

// ignore_for_file: experimental_member_use

import 'dart:async';
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

  /// Whether the `enroll:list` [inv] records asks for approved enrollments
  /// alone, as the approved section does; an approval's own read asks for
  /// pending and approved together.
  bool approvedFilter(Invocation inv) {
    final filter =
        (inv.namedArguments[#enrollmentListParams]
                as EnrollmentListRequestParam?)
            ?.enrollmentListFilter;
    return filter != null &&
        filter.length == 1 &&
        filter.single == EnrollmentStatus.approved;
  }

  Enrollment pendingRecord() => Enrollment()
    ..enrollmentId = enrollmentId
    ..appName = 'buzz'
    ..deviceName = 'pixel'
    ..status = 'pending'
    ..namespace = <String, String>{};

  Enrollment approvedRecord(String id, String device) => Enrollment()
    ..enrollmentId = id
    ..appName = 'buzz'
    ..deviceName = device
    ..status = 'approved'
    ..namespace = <String, String>{};

  /// Lists the pending request until [approvedYet] says the approval went
  /// through, and then lists it as approved: among [approvedAfter] for the
  /// approved section, and alone for an approval's own read.
  void listAround(
    bool Function() approvedYet, {
    List<Enrollment> approvedBefore = const [],
    required List<Enrollment> approvedAfter,
  }) {
    when(
      () => service.fetchEnrollmentRequests(
        enrollmentListParams: any(named: 'enrollmentListParams'),
      ),
    ).thenAnswer(
      (inv) async => approvedFilter(inv)
          ? (approvedYet() ? approvedAfter : approvedBefore)
          : (approvedYet()
                ? [approvedRecord(enrollmentId, 'pixel')]
                : [pendingRecord()]),
    );
  }

  setUpAll(() {
    registerFallbackValue(FakeEnrollmentRequestDecision());
    registerFallbackValue(FakeListParams());
    registerFallbackValue(AtKey());
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
    // which de-duplicates. A read of the approved enrollments finds none.
    when(
      () => service.fetchEnrollmentRequests(
        enrollmentListParams: any(named: 'enrollmentListParams'),
      ),
    ).thenAnswer(
      (inv) async => approvedFilter(inv) ? <Enrollment>[] : [pendingRecord()],
    );
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

  testWidgets(
    'the approved enrollments show whether their keys are anchored, naming a '
    'key that fails',
    (tester) async {
      Enrollment approved(String id, String device) => Enrollment()
        ..enrollmentId = id
        ..appName = 'buzz'
        ..deviceName = device
        ..status = 'approved'
        ..namespace = <String, String>{};
      when(
        () => service.fetchEnrollmentRequests(
          enrollmentListParams: any(named: 'enrollmentListParams'),
        ),
      ).thenAnswer(
        (inv) async => approvedFilter(inv)
            ? [
                approved('a-1', 'laptop'),
                approved('u-1', 'tablet'),
                approved('b-1', 'watch'),
              ]
            : [pendingRecord()],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentRequestList(
              atClient: atClient,
              anchoring: (id) async => switch (id) {
                'a-1' => ChainResult(ChainVerdict.anchored, [id], null),
                'u-1' => ChainResult(ChainVerdict.unsigned, [id], null),
                _ => ChainResult(
                  ChainVerdict.broken,
                  [id],
                  'a forged link',
                  kid: 'deadbeefdeadbeef',
                ),
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Approved enrollments'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('approved-a-1')),
          matching: find.text('anchored'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('approved-u-1')),
          matching: find.text('unsigned'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('approved-b-1')),
          matching: find.text('broken deadbeefdeadbeef'),
        ),
        findsOneWidget,
        reason:
            'a failing key is named, so the approver knows which key to '
            'look at',
      );
      expect(
        find.text('Approve'),
        findsOneWidget,
        reason: 'the pending request is still listed above them',
      );
    },
  );

  testWidgets(
    'a failure listing the approved enrollments shows in their section, and '
    'not as a failure of the pending list',
    (tester) async {
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
      ).thenAnswer((inv) async {
        if (approvedFilter(inv)) {
          throw AtClientException.message('list refused');
        }
        return <Enrollment>[];
      });

      await pumpList(tester);
      await tester.pump();

      expect(find.text('No pending enrollment requests'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(
        find.textContaining('Could not list the approved enrollments'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an approval stands when reading the approved enrollments again fails, '
    'and the section is read again after each approval',
    (tester) async {
      var approvedReads = 0;
      when(
        () => service.fetchEnrollmentRequests(
          enrollmentListParams: any(named: 'enrollmentListParams'),
        ),
      ).thenAnswer((inv) async {
        if (approvedFilter(inv)) {
          approvedReads++;
          if (approvedReads > 1) {
            throw AtClientException.message('list refused');
          }
          return <Enrollment>[];
        }
        return [pendingRecord()];
      });
      when(() => service.approve(any())).thenAnswer(
        (_) async =>
            AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
      );

      await pumpList(tester);
      expect(approvedReads, 1, reason: 'the premise: read once on opening');
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();

      expect(approvedReads, 2, reason: 'read again after the approval');
      expect(find.textContaining('Failed to approve'), findsNothing);
      expect(
        find.textContaining('Could not list the approved enrollments'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'given no anchoring, the approved section asks the client whether each '
    'enrollment is anchored',
    (tester) async {
      when(
        () => service.fetchEnrollmentRequests(
          enrollmentListParams: any(named: 'enrollmentListParams'),
        ),
      ).thenAnswer(
        (inv) async => approvedFilter(inv)
            ? [
                Enrollment()
                  ..enrollmentId = 'u-1'
                  ..appName = 'buzz'
                  ..deviceName = 'tablet'
                  ..status = 'approved'
                  ..namespace = <String, String>{},
              ]
            : [pendingRecord()],
      );
      when(
        () => atClient.get(
          any(),
          getRequestOptions: any(named: 'getRequestOptions'),
        ),
      ).thenThrow(AtKeyNotFoundException('no _apsk'));
      when(
        () => atClient.get(
          any(that: predicate<AtKey>((k) => '$k'.contains('.r.__e'))),
          getRequestOptions: any(named: 'getRequestOptions'),
        ),
      ).thenAnswer((_) async => AtValue()..value = 'withdrawn');

      await pumpList(tester);
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('approved-u-1')),
          matching: find.text('revoked'),
        ),
        findsOneWidget,
        reason:
            'an enrollment whose _apsk was moved to .r.__e reads revoked '
            'through client.enrollments.anchoring',
      );
    },
  );

  testWidgets(
    'a failed listing of the approved enrollments clears the rows it showed, '
    'and a later listing that succeeds clears the failure',
    (tester) async {
      Enrollment approved(String id) => Enrollment()
        ..enrollmentId = id
        ..appName = 'buzz'
        ..deviceName = 'device-$id'
        ..status = 'approved'
        ..namespace = <String, String>{};
      Enrollment pending(String id) => Enrollment()
        ..enrollmentId = id
        ..appName = 'buzz'
        ..deviceName = 'pixel-$id'
        ..status = 'pending'
        ..namespace = <String, String>{};
      var approvedReads = 0;
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
      ).thenAnswer((inv) async {
        if (!approvedFilter(inv)) return [pending('p-1'), pending('p-2')];
        approvedReads++;
        if (approvedReads == 2) throw AtClientException.message('refused');
        return [approved('a-1'), if (approvedReads > 2) approved('b-1')];
      });
      when(() => service.approve(any())).thenAnswer(
        (inv) async => AtEnrollmentResponse(
          (inv.positionalArguments.single as EnrollmentRequestDecision)
              .enrollmentId,
          EnrollmentStatus.approved,
        ),
      );
      Finder row(String id) => find.byKey(ValueKey('approved-$id'));
      final failure = find.textContaining(
        'Could not list the approved enrollments',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentRequestList(
              atClient: atClient,
              anchoring: (id) async =>
                  ChainResult(ChainVerdict.anchored, [id], null),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(row('a-1'), findsOneWidget, reason: 'the premise');

      await tester.tap(find.text('Approve').first);
      await tester.pump();
      await tester.pump();
      expect(failure, findsOneWidget);
      expect(
        row('a-1'),
        findsNothing,
        reason: 'rows from before the failure are not known to be current',
      );

      await tester.tap(find.text('Approve').first);
      await tester.pump();
      await tester.pump();
      expect(failure, findsNothing);
      expect(row('a-1'), findsOneWidget);
      expect(row('b-1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('Given an approval that goes through, when reading the approved '
      'enrollments then throws an error, then it does not say the approval '
      'failed', (tester) async {
    var approvedYet = false;
    when(() => service.approve(any())).thenAnswer((_) async {
      approvedYet = true;
      return AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved);
    });
    listAround(
      () => approvedYet,
      approvedAfter: [approvedRecord(enrollmentId, 'pixel')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrollmentRequestList(
            atClient: atClient,
            anchoring: (id) async => throw StateError('unreadable record'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Failed to approve'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'Given an approval whose conveyance is refused, when reading the approved '
    'enrollments then throws an error, then the refusal stands and nothing '
    'escapes',
    (tester) async {
      var approvedYet = false;
      when(() => service.approve(any())).thenAnswer((_) async {
        approvedYet = true;
        throw EnrollmentConveyanceException(
          'Enrollment $enrollmentId is approved, but no secrets were shared '
          'with it.',
          response: AtEnrollmentResponse(
            enrollmentId,
            EnrollmentStatus.approved,
          ),
          keyPackageStatus: KeyPackageStatus.rejected,
        );
      });
      listAround(
        () => approvedYet,
        approvedAfter: [approvedRecord(enrollmentId, 'pixel')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentRequestList(
              atClient: atClient,
              anchoring: (id) async => throw StateError('unreadable record'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('no secrets were shared'), findsOneWidget);
      expect(find.textContaining('Failed to approve'), findsNothing);
    },
  );

  testWidgets(
    'Given a slow first read of the approved enrollments, when an approval '
    'reloads them first, then the older read does not overwrite the newer '
    'rows',
    (tester) async {
      var approvedYet = false;
      final slow = Completer<ChainResult>();
      when(() => service.approve(any())).thenAnswer((_) async {
        approvedYet = true;
        return AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved);
      });
      listAround(
        () => approvedYet,
        approvedBefore: [approvedRecord('a-1', 'laptop')],
        approvedAfter: [
          approvedRecord('a-1', 'laptop'),
          approvedRecord(enrollmentId, 'pixel'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentRequestList(
              atClient: atClient,
              anchoring: (id) => approvedYet
                  ? Future.value(ChainResult(ChainVerdict.anchored, [id], null))
                  : slow.future,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('approved-$enrollmentId')),
        findsOneWidget,
        reason: 'the premise: the reload listed the newly approved enrollment',
      );

      slow.complete(ChainResult(ChainVerdict.unsigned, ['a-1'], null));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('approved-$enrollmentId')),
        findsOneWidget,
        reason: 'the older read must not overwrite the newer rows',
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'Given two approved enrollments, when the list reads whether each is '
    'anchored, then both reads start before either finishes',
    (tester) async {
      listAround(
        () => false,
        approvedBefore: [
          approvedRecord('a-1', 'laptop'),
          approvedRecord('a-2', 'phone'),
        ],
        approvedAfter: const [],
      );
      final started = <String>[];
      final reads = <String, Completer<ChainResult>>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentRequestList(
              atClient: atClient,
              anchoring: (id) {
                started.add(id);
                return (reads[id] = Completer<ChainResult>()).future;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(started, ['a-1', 'a-2']);
      for (final entry in reads.entries) {
        entry.value.complete(
          ChainResult(ChainVerdict.anchored, [entry.key], null),
        );
      }
      await tester.pump();
    },
  );

  testWidgets(
    'Given listing the approved enrollments throws an error, when the list '
    'loads, then it shows the failure and nothing escapes',
    (tester) async {
      when(
        () => service.fetchEnrollmentRequests(
          enrollmentListParams: any(named: 'enrollmentListParams'),
        ),
      ).thenAnswer(
        (inv) async => approvedFilter(inv)
            ? throw StateError('unreadable roster')
            : [pendingRecord()],
      );

      await pumpList(tester);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Could not list the approved enrollments'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Given a slow first listing that then fails, when an approval reloads the '
    'list first, then the failure does not replace the newer rows',
    (tester) async {
      var approvedYet = false;
      final slow = Completer<List<Enrollment>>();
      when(() => service.approve(any())).thenAnswer((_) async {
        approvedYet = true;
        return AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved);
      });
      when(
        () => service.fetchEnrollmentRequests(
          enrollmentListParams: any(named: 'enrollmentListParams'),
        ),
      ).thenAnswer((inv) async {
        if (!approvedFilter(inv)) {
          return approvedYet
              ? [approvedRecord(enrollmentId, 'pixel')]
              : [pendingRecord()];
        }
        return approvedYet
            ? [approvedRecord(enrollmentId, 'pixel')]
            : slow.future;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentRequestList(
              atClient: atClient,
              anchoring: (id) async =>
                  ChainResult(ChainVerdict.anchored, [id], null),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('approved-$enrollmentId')),
        findsOneWidget,
        reason: 'the premise: the reload listed the newly approved enrollment',
      );

      slow.completeError(AtClientException.message('refused'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('approved-$enrollmentId')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Could not list the approved enrollments'),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'Given an approval whose conveyance is refused, when it completes, then '
    'the approved enrollments are read again',
    (tester) async {
      var approvedYet = false;
      when(() => service.approve(any())).thenAnswer((_) async {
        approvedYet = true;
        throw EnrollmentConveyanceException(
          'Enrollment $enrollmentId is approved, but no secrets were shared '
          'with it.',
          response: AtEnrollmentResponse(
            enrollmentId,
            EnrollmentStatus.approved,
          ),
          keyPackageStatus: KeyPackageStatus.rejected,
        );
      });
      listAround(
        () => approvedYet,
        approvedAfter: [approvedRecord(enrollmentId, 'pixel')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentRequestList(
              atClient: atClient,
              anchoring: (id) async =>
                  ChainResult(ChainVerdict.anchored, [id], null),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('approved-$enrollmentId')),
        findsOneWidget,
      );
    },
  );
}
