import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() => '@alice';

  @override
  AtClientPreference getPreferences() => AtClientPreference();
}

class MockNotificationServiceImpl extends Mock
    implements NotificationServiceImpl {
  @override
  Stream<at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<at_notification.AtNotification>().stream;
  }
}

/// Pins that `stop()` actually stops: a sync run parked on its opening
/// network read (the stats fetch inside `_isInSync`) when `stop()` is
/// called must do no further sync work when it resumes, and `stop()`
/// must not return until that run has unwound.
///
/// The scenario is the one the functional pack caught red: a caller
/// awaits `stop()`, stages local writes on the promise that sync is
/// halted, and a run that entered processing before the stop resumes
/// from its network await and pushes the staged writes.
void main() {
  late MockAtClient atClient;
  late MockRemoteSecondary remote;
  late MockLocalSecondary local;
  late SyncServiceImpl service;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
  });

  setUp(() async {
    atClient = MockAtClient();
    remote = MockRemoteSecondary();
    local = MockLocalSecondary();
    final notificationService = MockNotificationServiceImpl();

    when(() => atClient.notificationService).thenReturn(notificationService);
    when(() => atClient.getLocalSecondary()).thenReturn(local);
    // lastReceivedServerCommitId reads (and _getLocalCommitId's pulled arm).
    when(() => atClient.get(any()))
        .thenAnswer((_) async => AtValue()..value = '7');
    // Five staged-but-unpushed local writes: what the resumed run reads,
    // and what it must NOT push once stopped.
    when(() => local.syncQueueSize).thenAnswer((_) async => 5);
    when(() => local.peekSyncQueue(limit: any(named: 'limit')))
        .thenAnswer((_) async => <String>[]);

    service = await SyncServiceImpl.create(atClient,
        atClientManager: MockAtClientManager(),
        remoteSecondary: remote,
        warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() async {
    if (!service.isStopped) {
      await service.stop();
    }
  });

  test('a run parked on the network when stop() lands does no work on resume',
      () async {
    final park = Completer<String>();
    when(() => remote.executeVerb(any())).thenAnswer((_) => park.future);

    SyncResult? errorResult;
    service.sync(onError: (result) => errorResult = result as SyncResult?);
    // The enqueue trigger runs on a microtask; after this await the run
    // has entered processSyncRequests and is parked on the stats fetch.
    await Future.delayed(Duration.zero);
    // Positive control: the run really is in flight on the network call.
    verify(() => remote.executeVerb(any())).called(1);

    final stopFuture = service.stop();
    // The network reply arrives after stop() — the red functional run's
    // exact shape. The resumed run sees five pending entries.
    park.complete('data:[{"value":"7"}]');
    await stopFuture;

    // The resumed run bailed before syncInternal: it never even took the
    // pending-push snapshot, let alone pushed.
    verifyNever(() => local.peekSyncQueue(limit: any(named: 'limit')));
    expect(errorResult, isNotNull,
        reason: 'the stranded request must be answered, not left dangling');
    expect(errorResult!.atClientException?.message,
        contains('has been stopped'),
        reason: 'the request is answered as stopped, not as any other error');
  });

  test('control: without stop(), the same parked run resumes and does work',
      () async {
    final park = Completer<String>();
    when(() => remote.executeVerb(any())).thenAnswer((_) => park.future);

    service.sync();
    await Future.delayed(Duration.zero);
    park.complete('data:[{"value":"7"}]');
    // Let the resumed run finish: server 7 == pulled 7 but five entries
    // are pending, so it is not in sync and syncInternal runs.
    await Future.delayed(Duration(milliseconds: 50));

    // The mechanism the first test guards actually runs when not stopped:
    // syncInternal took its pending-push snapshot. Without this arm, the
    // first test's verifyNever could pass because the path was never
    // reachable at all.
    verify(() => local.peekSyncQueue(limit: any(named: 'limit')))
        .called(greaterThanOrEqualTo(1));
  });

  test('stop() does not return while a run is in flight', () async {
    final park = Completer<String>();
    when(() => remote.executeVerb(any())).thenAnswer((_) => park.future);

    service.sync();
    await Future.delayed(Duration.zero);

    var stopped = false;
    final stopFuture = service.stop().then((_) => stopped = true);
    await Future.delayed(Duration(milliseconds: 20));
    expect(stopped, false,
        reason: 'stop() must wait for the in-flight run to unwind');

    park.complete('data:[{"value":"7"}]');
    await stopFuture;
    expect(stopped, true);
  });
}
