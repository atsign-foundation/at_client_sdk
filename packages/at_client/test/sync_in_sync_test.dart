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

class _Progress implements SyncProgressListener {
  final List<SyncProgress> events = [];

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) =>
      events.add(syncProgress);
}

/// A client that has pulled everything its filter admits, with nothing
/// waiting to push, is in sync. A filtered client's server figure is the
/// highest commit id among the entries its filter admits, which drops below
/// the client's cursor when the newest such entry is purged.
void main() {
  late _MockAtClient atClient;
  late _MockLocalSecondary localSecondary;
  late _MockRemoteSecondary remote;
  late StreamController<AtNotification> stats;
  late SyncServiceImpl sync;

  /// What `stats:3` answers, and what the client has pulled up to.
  late int serverFigure;
  late int cursor;
  late int pendingPushes;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  setUp(() async {
    serverFigure = 0;
    cursor = 0;
    pendingPushes = 0;
    atClient = _MockAtClient();
    localSecondary = _MockLocalSecondary();
    remote = _MockRemoteSecondary();
    stats = StreamController<AtNotification>.broadcast();
    when(() => atClient.getCurrentAtSign()).thenReturn('@filtered');
    when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
    final notifications = _MockNotificationService();
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => stats.stream);
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.getPreferences())
        .thenReturn(AtClientPreference()..syncRegex = 'wavi');
    when(() => atClient.get(any()))
        .thenAnswer((_) async => AtValue()..value = '$cursor');
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => localSecondary.isWriteInProgress(any())).thenReturn(false);
    when(() => localSecondary.syncQueueSize)
        .thenAnswer((_) async => pendingPushes);
    when(() => localSecondary.peekSyncQueue())
        .thenAnswer((_) async => <String>[]);
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is StatsVerbBuilder) {
        return 'data:[{"id":"3","name":"lastCommitID","value":"$serverFigure"}]';
      }
      if (builder is SyncVerbBuilder) return 'data:[]';
      throw StateError(
          'no answer for ${(builder as VerbBuilder).buildCommand()}');
    });
    sync = await SyncServiceImpl.create(atClient,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() async {
    await sync.stop();
    await stats.close();
  });

  /// The progress messages of one round an app requested.
  Future<List<String?>> roundMessages() async {
    final progress = _Progress();
    sync.addProgressListener(progress);
    sync.syncRequests.addLast(SyncRequest()
      ..requestSource = SyncRequestSource.app
      ..result = SyncResult());
    await sync.processSyncRequests();
    return progress.events.map((e) => e.message).toList();
  }

  group('isInSync()', () {
    test('a server figure below the cursor is caught up', () async {
      cursor = 120;
      serverFigure = 100;

      expect(await sync.isInSync(), isTrue,
          reason: 'the newest entry the filter admits was purged, so the '
              'figure fell below what the client has already pulled');
    });

    test('a server figure equal to the cursor is caught up', () async {
      cursor = 120;
      serverFigure = 120;

      expect(await sync.isInSync(), isTrue);
    });

    test('a server figure above the cursor is not', () async {
      cursor = 120;
      serverFigure = 130;

      expect(await sync.isInSync(), isFalse,
          reason: 'the atServer holds an entry the client has not pulled');
    });

    test('a write waiting to push is not, whatever the figure', () async {
      cursor = 120;
      serverFigure = 100;
      pendingPushes = 1;

      expect(await sync.isInSync(), isFalse);
    });
  });

  group('a round an app requests', () {
    test('finds the client in sync with the server figure below the cursor',
        () async {
      cursor = 120;
      serverFigure = 100;

      expect(await roundMessages(), contains('server and local are in sync'),
          reason: 'the round decides with the same rule isInSync() answers by');
    });

    test('finds the client in sync with the server figure equal to the cursor',
        () async {
      cursor = 120;
      serverFigure = 120;

      expect(await roundMessages(), contains('server and local are in sync'));
    });
  });
}
