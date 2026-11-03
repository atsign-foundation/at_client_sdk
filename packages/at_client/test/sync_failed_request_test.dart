import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockAtClient extends Mock implements AtClient {}

class _MockLocalSecondary extends Mock implements LocalSecondary {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

class _Progress implements SyncProgressListener {
  final List<SyncProgress> events = [];

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) =>
      events.add(syncProgress);
}

/// A sync service whose round fails, and the request that asked for it.
void main() {
  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
  });

  late _MockRemoteSecondary remote;
  late SyncServiceImpl sync;

  setUp(() async {
    final atClient = _MockAtClient();
    final localSecondary = _MockLocalSecondary();
    remote = _MockRemoteSecondary();
    when(() => atClient.getCurrentAtSign()).thenReturn('@failed');
    when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
    final notifications = _MockNotificationService();
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => const Stream<AtNotification>.empty());
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
    when(() => atClient.get(any()))
        .thenThrow(AtKeyNotFoundException('nothing persisted yet'));
    when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 0);
    when(() => localSecondary.peekSyncQueue())
        .thenAnswer((_) async => <String>[]);
    // NOTE: fails after an event-loop turn, as a real connection does. A
    // synchronous failure turns the defect into a microtask loop that starves
    // this test's own timer, so a regression would hang rather than fail.
    when(() => remote.executeVerb(any())).thenAnswer((_) async {
      await Future<void>.delayed(Duration.zero);
      throw AtConnectException('Connection refused');
    });
    sync = await SyncServiceImpl.create(atClient,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() => sync.stop());

  test(
      'a request the round fails is reported once, and the round is not run '
      'again for it', () async {
    final progress = _Progress();
    sync.addProgressListener(progress);
    sync.sync();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(progress.events.where((e) => e.syncStatus == SyncStatus.failure),
        hasLength(1),
        reason: 'a request left queued after its round failed would run the '
            'same round again on the next microtask, reporting a failure each '
            'time');
    verify(() => remote.executeVerb(any())).called(1);
  });
}
