import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

var mockCommitLogStore = {};

class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {
  Map<String, AtData> localKeyStore = {
    'mobile.wavi': AtData()..data = '12345',
    'country.wavi': AtData()..data = 'India',
    'location.wavi': AtData()..data = 'Hyderabad',
    'about.wavi': AtData()..data = '@sign',
    'phone.wavi': AtData()..data = '12345'
  };

  @override
  Future<AtData> get(key) async {
    return Future.value(localKeyStore[key]);
  }

  @override
  bool isKeyExists(String key) {
    if (key.startsWith('local:lastreceivedservercommitid')) {
      return false;
    }
    return true;
  }
}

class MockLocalSecondary extends Mock implements LocalSecondary {
  @override
  SecondaryKeyStore get keyStore => MockSecondaryKeyStore();
}

class MockRemoteSecondary extends Mock implements RemoteSecondary {
  var remoteKeyStore = {};
}

class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() {
    return '@alice';
  }

  @override
  AtClientPreference getPreferences() {
    return AtClientPreference();
  }
}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockNotificationServiceImpl extends Mock
    implements NotificationServiceImpl {
  @override
  Stream<at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<at_notification.AtNotification>().stream;
  }
}

class MockAtCommitLog extends Mock implements AtCommitLog {
  @override
  Future<void> update(CommitEntry commitEntry, int commitId) async {
    mockCommitLogStore.putIfAbsent(
        commitId, () => commitEntry..commitId = commitId);
  }
}

class FakeSyncVerbBuilder extends Fake implements SyncVerbBuilder {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

class FakeStatsVerbBuilder extends Fake implements StatsVerbBuilder {}

class FakeAtKey extends Fake implements AtKey {}

void main() async {
  late AtClient mockAtClient;
  late AtClientManager mockAtClientManager;
  late NotificationServiceImpl mockNotificationService;
  late AtCommitLog mockAtCommitLog;
  late RemoteSecondary mockRemoteSecondary;
  late LocalSecondary mockLocalSecondary;
  late SyncServiceImpl syncServiceImpl;

  setUp(() async {
    mockAtClient = MockAtClient();
    mockAtClientManager = MockAtClientManager();
    mockNotificationService = MockNotificationServiceImpl();
    mockAtCommitLog = MockAtCommitLog();
    mockRemoteSecondary = MockRemoteSecondary();
    mockLocalSecondary = MockLocalSecondary();

    when(() => mockAtClient.notificationService)
        .thenReturn(mockNotificationService);

    syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
        atClientManager: mockAtClientManager,
        remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
    syncServiceImpl.syncUtil = SyncUtil(atCommitLog: mockAtCommitLog);
  });

  group('A group of positive tests on sync service', () {
    var localCommitId = -1;
    test('sync server changes to local', () async {
      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeUpdateVerbBuilder());
      registerFallbackValue(FakeAtKey());

      when(() => mockAtClient.put(
              any(that: LastReceivedServerCommitIdMatcher()), any()))
          .thenAnswer((_) => Future.value(true));
      when(() =>
              mockAtClient.put(any(that: InitialSyncDoneFlagMatcher()), any()))
          .thenAnswer((_) => Future.value(true));
      when(() => mockRemoteSecondary.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:${jsonEncode([
                    {
                      "atKey": "public:twitter.wavi@alice",
                      "value": "twitter.alice",
                      "metadata": {
                        "createdAt": "2021-04-08 12:59:19.251",
                        "updatedAt": "2021-04-08 12:59:19.251"
                      },
                      "commitId": 1,
                      "operation": "+"
                    },
                    {
                      "atKey": "public:instagram.wavi@alice",
                      "value": "instagram.alice",
                      "metadata": {
                        "createdAt": "2021-04-08 07:39:27.616Z",
                        "updatedAt": "2022-06-30 09:41:59.264Z"
                      },
                      "commitId": 2,
                      "operation": "*"
                    }
                  ])}'));

      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);
      when(() => mockLocalSecondary.executeVerb(any(), sync: false))
          .thenAnswer((_) => Future.value('data:${++localCommitId}'));
      when(() => mockAtCommitLog.lastSyncedEntry()).thenAnswer((_) =>
          Future.value(
              CommitEntry('phone.wavi', CommitOp.UPDATE, DateTime.now())
                ..commitId = localCommitId));
      when(() => mockAtCommitLog.getChanges(any(), any()))
          .thenAnswer((_) => Future.value([]));
      when(() => mockAtCommitLog.getEntry(any())).thenAnswer((_) =>
          Future.value(
              CommitEntry('phone.wavi', CommitOp.UPDATE, DateTime.now())
                ..commitId = localCommitId));
      when(() =>
              mockAtClient.get(any(that: LastReceivedServerCommitIdMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));
      when(() => mockAtClient.get(any(that: SkipDeletesUntilMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));
      when(() => mockAtClient.get(any(that: InitialSyncDoneFlagMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));

      var serverCommitId = 2;
      var syncRequest = SyncRequest()..result = SyncResult();
      await syncServiceImpl.syncInternal(serverCommitId, syncRequest);
      expect(mockCommitLogStore.isNotEmpty, true);
      mockCommitLogStore.clear();
    });
  });

  group('A group of tests to validate exception chaining in sync service', () {
    test('A test to validate server responds with AtTimeOutException',
        () async {
      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeAtKey());
      var localCommitId = -1;

      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);
      when(() => mockAtClient.put(
              any(that: LastReceivedServerCommitIdMatcher()), any()))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.put(any(that: SkipDeletesUntilMatcher()), any()))
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtCommitLog.lastSyncedEntry()).thenAnswer((_) =>
          Future.value(
              CommitEntry('phone.wavi', CommitOp.UPDATE, DateTime.now())
                ..commitId = localCommitId));
      when(() => mockAtCommitLog.getChanges(any(), any()))
          .thenAnswer((_) => Future.value([]));
      when(() => mockRemoteSecondary
              .executeVerb(any(that: isA<SyncVerbBuilder>())))
          .thenThrow(AtTimeoutException(
              'Waited for 10000 millis. No response after 90000',
              intent: Intent.syncData,
              exceptionScenario: ExceptionScenario.remoteVerbExecutionFailed));
      when(() => mockRemoteSecondary
              .executeVerb(any(that: isA<StatsVerbBuilder>())))
          .thenAnswer((_) => Future.value('data:${jsonEncode([
                    {"id": "3", "name": "lastCommitID", "value": "5"}
                  ])}'));
      when(() =>
              mockAtClient.get(any(that: LastReceivedServerCommitIdMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));
      when(() => mockAtClient.get(any(that: SkipDeletesUntilMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));
      when(() => mockAtClient.get(any(that: InitialSyncDoneFlagMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));

      // ignore: prefer_typing_uninitialized_variables
      var actualSyncException;

      var listener = MySyncProgressListener();
      syncServiceImpl.addProgressListener(listener);
      syncServiceImpl.sync(onError: (SyncResult syncResult) {
        actualSyncException = syncResult.atClientException;
      });

      await syncServiceImpl.processSyncRequests();

      while (!listener.syncComplete) {
        await Future.delayed(Duration(milliseconds: 10));
      }

      expect(actualSyncException, isA<AtClientException>());
      expect(actualSyncException.getTraceMessage(),
          'Failed to syncData caused by\nWaited for 10000 millis. No response after 90000');
    });
  });

  group('A group of tests to validate exception during sync processing', () {
    var localCommitId = -1;
    test('invalid batch json from server', () async {
      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeUpdateVerbBuilder());
      registerFallbackValue(FakeAtKey());

      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);
      when(() => mockAtClient.put(
              any(that: LastReceivedServerCommitIdMatcher()), any()))
          .thenAnswer((_) => Future.value(true));
      when(() => mockRemoteSecondary.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:${jsonEncode([
                    {
                      "atKey": "public:twitter.wavi@alice",
                      "value": "twitter.alice",
                      "metadata": {
                        "createdAt": "2021-04-08 12:59:19.251",
                        "updatedAt": "2021-04-08 12:59:19.251"
                      },
                      "commitId": 1,
                      "operation": "+"
                    },
                    {
                      "atKey": "public:insta.buzz@alice",
                      "value": "insta_buzz",
                      "metadata": {
                        "createdAt": "2021-04-08 07:39:27.616Z",
                        "updatedAt": "2022-06-30 09:41:59.264Z"
                      },
                      "commitId": '2', //invalid data type
                      "operation": "*"
                    },
                    {
                      "atKey": "public:instagram.wavi@alice",
                      "value": "instagram.alice",
                      "metadata": {
                        "createdAt": "2021-04-08 07:39:27.616Z",
                        "updatedAt": "2022-06-30 09:41:59.264Z"
                      },
                      "commitId": 3,
                      "operation": "*"
                    }
                  ])}'));

      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);
      when(() => mockLocalSecondary.executeVerb(any(), sync: false))
          .thenAnswer((_) => Future.value('data:${++localCommitId}'));
      when(() => mockAtCommitLog.lastSyncedEntry()).thenAnswer((_) =>
          Future.value(
              CommitEntry('phone.wavi', CommitOp.UPDATE, DateTime.now())
                ..commitId = localCommitId));
      when(() => mockAtCommitLog.getChanges(any(), any()))
          .thenAnswer((_) => Future.value([]));
      when(() => mockAtCommitLog.getEntry(any())).thenAnswer((_) =>
          Future.value(
              CommitEntry('phone.wavi', CommitOp.UPDATE, DateTime.now())
                ..commitId = localCommitId));
      when(() =>
              mockAtClient.get(any(that: LastReceivedServerCommitIdMatcher())))
          .thenAnswer((invocation) {
        throw AtKeyNotFoundException('key is not found in keystore');
      });
      when(() => mockAtClient.get(any(that: SkipDeletesUntilMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));
      when(() => mockAtClient.get(any(that: InitialSyncDoneFlagMatcher())))
          .thenAnswer((invocation) =>
              throw AtKeyNotFoundException('key is not found in keystore'));

      var serverCommitId = 2;
      var syncRequest = SyncRequest()..result = SyncResult();
      print('calling sync internal');
      final syncResult =
          await syncServiceImpl.syncInternal(serverCommitId, syncRequest);
      expect(syncResult.keyInfoList, isNotEmpty);
      expect(syncResult.keyInfoList.length, 2);
      expect(syncResult.keyInfoList[0].key, 'public:twitter.wavi@alice');
      expect(syncResult.keyInfoList[1].key, 'public:instagram.wavi@alice');
      mockCommitLogStore.clear();
    });
  });

  group('Validate SyncService stop() behaviour', () {
    test('stop() should stop the sync service', () async {
      await syncServiceImpl.stop();
      expect(syncServiceImpl.isStopped, true);
    });

    test('stop() should not stop the sync service if it is already stopped',
        () async {
      await syncServiceImpl.stop();
      expect(syncServiceImpl.isStopped, true);
    });

    test('stop() should drain the pending requests', () async {
      syncServiceImpl.sync();
      syncServiceImpl.sync();
      syncServiceImpl.sync();
      expect(syncServiceImpl.syncRequests.length, 3);

      await syncServiceImpl.stop();
      expect(syncServiceImpl.isStopped, true);
      expect(syncServiceImpl.syncRequests.length, 0);
    });

    test('stop() should gracefully close mid-sync and notify listeners',
        () async {
      registerFallbackValue(FakeUpdateVerbBuilder());
      registerFallbackValue(FakeAtKey());

      // local has uncommitted DELETE entries while server is at commit 5 —
      // isSyncInProgress will be true while the batch push is in-flight
      when(() => mockRemoteSecondary
              .executeVerb(any(that: isA<StatsVerbBuilder>())))
          .thenAnswer((_) => Future.value('data:${jsonEncode([
                    {"id": "3", "name": "lastCommitID", "value": "5"}
                  ])}'));
      when(() =>
              mockAtClient.get(any(that: LastReceivedServerCommitIdMatcher())))
          .thenAnswer((_) => Future.value(AtValue()..value = '5'));
      when(() => mockAtCommitLog.lastSyncedEntry())
          .thenAnswer((_) => Future.value(null));
      // uncommitted local entries → _isInSync() returns false
      when(() => mockAtCommitLog.getChanges(any(), any()))
          .thenAnswer((_) => Future.value([
                CommitEntry('phone.wavi', CommitOp.DELETE, DateTime.now()),
                CommitEntry('mobile.wavi', CommitOp.DELETE, DateTime.now()),
              ]));
      when(() => mockRemoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async {
        await Future.delayed(Duration(milliseconds: 300));
        return 'data:[{"id":1,"response":{"data":"10"}},{"id":2,"response":{"data":"11"}}]';
      });

      MockSyncProgressListener syncProgressListener =
          MockSyncProgressListener();
      syncServiceImpl.addProgressListener(syncProgressListener);

      int syncFailureCount = 0;
      // queue requests and start processing, then stop mid-sync
      syncServiceImpl.sync(onError: () => syncFailureCount++);
      syncServiceImpl.sync(onError: () => syncFailureCount++);
      syncServiceImpl.sync(onError: () => syncFailureCount++);
      syncServiceImpl.sync(onError: () => syncFailureCount++);
      syncServiceImpl.sync(onError: () => syncFailureCount++);

      expect(syncServiceImpl.syncRequests.length, 5);
      unawaited(syncServiceImpl.processSyncRequests());
      await Future.delayed(Duration(milliseconds: 200));
      expect(syncServiceImpl.isSyncInProgress, true);

      await syncServiceImpl.stop();
      expect(syncServiceImpl.isStopped, true);
      expect(syncServiceImpl.syncRequests.length, 0);
      expect(syncProgressListener.syncFailed, true);
    });
  });
}

class MySyncProgressListener extends SyncProgressListener {
  bool syncComplete = false;

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    if (syncProgress.syncStatus == SyncStatus.failure ||
        syncProgress.syncStatus == SyncStatus.success) {
      syncComplete = true;
    }
    return;
  }
}

class MockSyncProgressListener extends SyncProgressListener {
  bool syncFailed = false;

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    if (syncProgress.syncStatus == SyncStatus.failure) {
      syncFailed = true;
    }
  }
}

class LastReceivedServerCommitIdMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is AtKey && item.key.startsWith('lastreceivedservercommitid')) {
      return true;
    }
    return false;
  }
}

class SkipDeletesUntilMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is AtKey && item.key.startsWith('skipdeletesuntil')) {
      return true;
    }
    return false;
  }
}

class InitialSyncDoneFlagMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is AtKey && item.key.startsWith('isinitialsyncdone')) {
      return true;
    }
    return false;
  }
}
