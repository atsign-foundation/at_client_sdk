import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// NOTE: this file previously also held four mock-driven tests for the
// server→client pull path, server-timeout error chaining, invalid-batch
// JSON handling, and mid-sync stop(). All four mocked the (now removed)
// commit-log push path and were already `skip:`-marked obsolete; they
// are retired here. The equivalent behaviour is exercised end-to-end by
// `tests/at_functional_test/test/atclient_sync_test.dart` and
// `atclient_sync_conflict_test.dart`. The queue-based push path has unit
// coverage in `local_secondary_sync_queue_test.dart`.

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() => '@alice';

  @override
  AtClientPreference getPreferences() => AtClientPreference();
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

void main() async {
  late AtClient mockAtClient;
  late AtClientManager mockAtClientManager;
  late NotificationServiceImpl mockNotificationService;
  late RemoteSecondary mockRemoteSecondary;
  late SyncServiceImpl syncServiceImpl;

  setUp(() async {
    mockAtClient = MockAtClient();
    mockAtClientManager = MockAtClientManager();
    mockNotificationService = MockNotificationServiceImpl();
    mockRemoteSecondary = MockRemoteSecondary();

    when(() => mockAtClient.notificationService)
        .thenReturn(mockNotificationService);

    syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
        atClientManager: mockAtClientManager,
        remoteSecondary: mockRemoteSecondary,
        warmStartSync: false) as SyncServiceImpl;
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
  });
}
