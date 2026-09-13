import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockAtClient extends Mock implements AtClient {}

class _MockLocalSecondary extends Mock implements LocalSecondary {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

/// An app's `sync()` is a demand for a fresh answer; a stats notification is
/// news the service has already taken in. A round reads the server fresh
/// whenever an app is waiting on it, whichever request it dequeues, and a
/// stats notification never pushes an app's request out of a full queue.
void main() {
  late _MockAtClient atClient;
  late _MockLocalSecondary localSecondary;
  late _MockRemoteSecondary remote;
  late StreamController<AtNotification> stats;
  late SyncServiceImpl sync;
  late int statsFetches;

  AtNotification statsNotification(String commitId) => AtNotification(
      'n-$commitId',
      'statsNotification.monitorKey@fresh',
      '@fresh',
      '@fresh',
      1,
      MessageTypeEnum.key.toString(),
      false,
      value: commitId);

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  setUp(() async {
    SyncServiceImpl.queueSize = 10;
    atClient = _MockAtClient();
    localSecondary = _MockLocalSecondary();
    remote = _MockRemoteSecondary();
    stats = StreamController<AtNotification>.broadcast();
    statsFetches = 0;
    when(() => atClient.getCurrentAtSign()).thenReturn('@fresh');
    when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
    final notifications = _MockNotificationService();
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => stats.stream);
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
    when(() => atClient.get(any()))
        .thenThrow(AtKeyNotFoundException('nothing persisted yet'));
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => localSecondary.isWriteInProgress(any())).thenReturn(false);
    when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 0);
    when(() => localSecondary.peekSyncQueue())
        .thenAnswer((_) async => <String>[]);
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is StatsVerbBuilder) {
        statsFetches++;
        return 'data:[{"id":"3","name":"lastCommitID","value":"5"}]';
      }
      if (builder is SyncVerbBuilder) return 'data:[]';
      throw StateError(
          'no answer for ${(builder as VerbBuilder).buildCommand()}');
    });
    sync = await SyncServiceImpl.create(atClient,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() async {
    SyncServiceImpl.queueSize = 10;
    await stats.close();
  });

  /// One round, driven by a stats notification, so the service holds a
  /// cached server commit id and its pull cursor has caught up with it.
  Future<void> settledOnCachedCommitId() async {
    stats.add(statsNotification('5'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    while (sync.isSyncInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(statsFetches, 0,
        reason: 'the notification promoted the cache, so nothing fetched');
  }

  test(
      'a round reads the server fresh when an app request is queued behind '
      'a system one', () async {
    await settledOnCachedCommitId();
    when(() => atClient.get(any()))
        .thenAnswer((_) async => AtValue()..value = '5');
    sync.syncRequests
      ..addLast(SyncRequest()
        ..requestSource = SyncRequestSource.system
        ..result = SyncResult())
      ..addLast(SyncRequest()
        ..requestSource = SyncRequestSource.app
        ..result = SyncResult());

    await sync.processSyncRequests();

    expect(statsFetches, 1,
        reason: 'the system request was dequeued first, and the app request '
            'behind it is a demand for a fresh answer; the cached id said '
            '"in sync" and would have been the answer to both');
  });

  test(
      'a stats notification does not push an app request out of a full '
      'queue', () async {
    SyncServiceImpl.queueSize = 1;
    final gate = Completer<List<String>>();
    when(() => localSecondary.peekSyncQueue()).thenAnswer((_) => gate.future);
    var evicted = false;
    sync.sync(onError: (_) => evicted = true);
    // The round is parked on its first read of the sync queue.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sync.isSyncInProgress, isTrue);

    sync.sync(onError: (_) => evicted = true);
    expect(sync.syncRequests.single.requestSource, SyncRequestSource.app);
    stats.add(statsNotification('6'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(sync.syncRequests.single.requestSource, SyncRequestSource.app,
        reason: 'the notification\'s commit id is already in the cache; the '
            'app\'s request is the only thing that would read fresh');
    expect(evicted, isFalse,
        reason: 'and the app was not told its request was superseded');

    gate.complete(<String>[]);
    while (sync.isSyncInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}
