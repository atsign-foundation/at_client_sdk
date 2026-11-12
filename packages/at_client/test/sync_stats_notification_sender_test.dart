import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/transport.dart';

class _IdleMonitor extends Fake implements Monitor {
  @override
  NotificationListenerState currentState =
      NotificationListenerState.notConnected;
  @override
  NotificationListenerState targetState =
      NotificationListenerState.notConnected;
  @override
  Future<void> start({int? lastNotificationTime}) async {}
  @override
  void stop() {}
  @override
  Stream<NotificationListenerState> get currentStateStream =>
      const Stream.empty();
}

/// Sync's stats listener moves the sync state only on the atServer's stats
/// notification for this client's own atSign, delivered through the real
/// notification service, with a pull cursor that persists.
void main() {
  const alice = '@alice';
  const namespace = 'stats_sender';
  final cursorKey =
      AtKey.local('lastreceivedservercommitid', alice, namespace: namespace)
          .build()
          .toString();

  late MockAtClientImpl atClient;
  late MockRemoteSecondary remote;
  late NotificationServiceImpl notifications;
  late SyncServiceImpl sync;
  late Map<String, String> store;
  late List<int> pullsFrom;
  late int serverHead;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  setUp(() async {
    SyncServiceImpl.queueSize = 10;
    atClient = MockAtClientImpl();
    final localSecondary = MockLocalSecondary();
    remote = MockRemoteSecondary();
    store = {cursorKey: '5'};
    pullsFrom = [];
    serverHead = 5;
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    when(() => atClient.atSign).thenReturn(alice.toAtsign());
    when(() => atClient.enrollmentId).thenReturn(null);
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
      ..namespace = namespace
      ..monitorAutoStart = false);
    when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final key = (inv.positionalArguments.first as AtKey).toString();
      final value = store[key];
      if (value == null) throw AtKeyNotFoundException(key);
      return AtValue()..value = value;
    });
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      store[(inv.positionalArguments.first as AtKey).toString()] =
          inv.positionalArguments[1].toString();
      return true;
    });
    when(() => localSecondary.isWriteInProgress(any())).thenReturn(false);
    when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 0);
    when(() => localSecondary.peekSyncQueue())
        .thenAnswer((_) async => <String>[]);
    when(() => remote.executeVerb(any())).thenAnswer((inv) async {
      final builder = inv.positionalArguments.first;
      if (builder is StatsVerbBuilder) {
        return 'data:[{"id":"3","name":"lastCommitID","value":"$serverHead"}]';
      }
      if (builder is SyncVerbBuilder) {
        pullsFrom.add(builder.commitId);
        return 'data:[]';
      }
      throw StateError('unexpected ${(builder as VerbBuilder).buildCommand()}');
    });
    notifications = await NotificationServiceImpl.create(atClient,
        monitor: _IdleMonitor(),
        secondaryAddressFinder: defaultAtDirectory) as NotificationServiceImpl;
    when(() => atClient.notificationService).thenReturn(notifications);
    sync = await SyncServiceImpl.create(atClient,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() async {
    await sync.stop();
    notifications.stopAllSubscriptions();
  });

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    while (sync.isSyncInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<void> receive(
      {required String id,
      required String key,
      required String from,
      required int commitId}) async {
    await notifications.handleNotificationReceipt('notification: ${jsonEncode({
          'id': id,
          'key': key,
          'from': from,
          'to': alice,
          'epochMillis': DateTime.now().millisecondsSinceEpoch,
          'value': '$commitId',
          'operation': 'update',
          'messageType': MessageTypeEnum.key.toString(),
          AtConstants.isEncrypted: false,
        })}\n');
    await settle();
  }

  /// The notification the atServer writes to its own atSign's monitor.
  Future<void> ownStats(int commitId) => receive(
      id: '-1',
      key: 'statsNotification.$alice',
      from: alice,
      commitId: commitId);

  group('Given the atServer\'s stats notification for the client\'s own atSign',
      () {
    test(
        'when sync receives it, then a sync runs and the saved pull cursor '
        'moves to its commit id', () async {
      serverHead = 6;
      await ownStats(6);

      expect(pullsFrom, [5]);
      expect(store[cursorKey], '6');
    });

    test('when its sender is spelt in another case, then sync still acts on it',
        () async {
      serverHead = 6;
      await receive(
          id: '-1',
          key: 'statsNotification.$alice',
          from: '@Alice',
          commitId: 6);

      expect(pullsFrom, [5],
          reason: 'the sender is compared in canonical form');
    });
  });

  group(
      'Given a stats notification that didn\'t come from the client\'s own '
      'atSign', () {
    test(
        'when sync receives it, then the saved pull cursor is unchanged and no '
        'sync runs because of it', () async {
      await receive(
          id: 'n-1',
          key: '$alice:statsNotification.x@bob',
          from: '@bob',
          commitId: 6);

      expect(pullsFrom, isEmpty);
      expect(store[cursorKey], '5');

      await receive(
          id: 'n-2',
          key: 'statsNotification.$alice',
          from: '@bob',
          commitId: 6);

      expect(pullsFrom, isEmpty,
          reason: 'the sender decides, even when the key is the stats key');
      expect(store[cursorKey], '5');

      serverHead = 6;
      await ownStats(6);
      expect(pullsFrom, [5],
          reason: 'the atServer\'s own stats notification still drives sync');
      expect(store[cursorKey], '6');
    });
  });

  group(
      'Given a notification from the client\'s own atSign whose key is not '
      'its stats key', () {
    test(
        'when sync receives it, then the saved pull cursor is unchanged and no '
        'sync runs because of it', () async {
      await receive(
          id: 'n-2',
          key: '$alice:statsNotification.x$alice',
          from: alice,
          commitId: 6);

      expect(pullsFrom, isEmpty);
      expect(store[cursorKey], '5');
    });
  });
}
