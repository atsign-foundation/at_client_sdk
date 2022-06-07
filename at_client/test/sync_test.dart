import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart'
    as _at_notification;
import 'package:at_client/src/service/sync/sync_request.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/util/sync_util.dart';
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
}

class MockLocalSecondary extends Mock implements LocalSecondary {
  @override
  SecondaryKeyStore? get keyStore => MockSecondaryKeyStore();
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
  AtClientPreference? getPreferences() {
    return AtClientPreference();
  }

  @override
  LocalSecondary? getLocalSecondary() {
    return MockLocalSecondary();
  }
}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockNotificationServiceImpl extends Mock
    implements NotificationServiceImpl {
  @override
  Stream<_at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<_at_notification.AtNotification>().stream;
  }
}

class MockAtCommitLog extends Mock implements AtCommitLog {
  @override
  Future<CommitEntry?> lastSyncedEntry() async {
    return CommitEntry('phone.wavi', CommitOp.UPDATE, DateTime.now())
      ..commitId = 5;
  }

  @override
  Future<List<CommitEntry>> getChanges(int? sequenceNumber, String? regex,
      {int? limit}) async {
    return [
      CommitEntry('mobile.wavi', CommitOp.UPDATE, DateTime.now())..commitId = 1,
      CommitEntry('country.wavi', CommitOp.UPDATE, DateTime.now())
        ..commitId = 2,
      CommitEntry('location.wavi', CommitOp.UPDATE, DateTime.now())
        ..commitId = 3,
      CommitEntry('about.wavi', CommitOp.UPDATE, DateTime.now())..commitId = 4,
      CommitEntry('phone.wavi', CommitOp.UPDATE, DateTime.now())..commitId = 5,
    ];
  }

  @override
  Future<void> update(CommitEntry commitEntry, int commitId) async {
    mockCommitLogStore.putIfAbsent(
        commitId, () => commitEntry..commitId = commitId);
  }
}

void main() async {
  AtClient mockAtClient = MockAtClient();
  AtClientManager mockAtClientManager = MockAtClientManager();
  NotificationServiceImpl mockNotificationService =
      MockNotificationServiceImpl();
  AtCommitLog mockAtCommitLog = MockAtCommitLog();
  RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();

  var syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
      atClientManager: mockAtClientManager,
      notificationService: mockNotificationService,
      remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
  syncServiceImpl.syncUtil = SyncUtil(atCommitLog: mockAtCommitLog);

  test('sync local changes when server is reset', () async {
    when(() => mockRemoteSecondary
            .executeCommand(any(that: startsWith('batch:')), auth: true))
        .thenAnswer((_) => Future.value('data:${jsonEncode([
                  {
                    "id": 1,
                    "response": {"data": "1"}
                  },
                  {
                    "id": 2,
                    "response": {"data": "2"}
                  },
                  {
                    "id": 3,
                    "response": {"data": "3"}
                  },
                  {
                    "id": 4,
                    "response": {"data": "4"}
                  }
                ])}'));
    var serverCommitId = -1;
    var syncRequest = SyncRequest()..result = SyncResult();
    await syncServiceImpl.syncInternal(serverCommitId, syncRequest);
    expect(mockCommitLogStore.isNotEmpty, true);
    mockCommitLogStore.clear();
  });
}
