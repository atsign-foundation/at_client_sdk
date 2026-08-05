import 'dart:async';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;

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
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;

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

/// Matches the reserved `skipdeletesuntil...` AtKey that
/// `SyncServiceImpl.setAndGetSkipDeletesUntil` reads/writes.
class SkipDeletesUntilMatcher extends Matcher {
  @override
  Description describe(Description description) => description;

  @override
  bool matches(item, Map matchState) =>
      item is AtKey && item.key.startsWith('skipdeletesuntil');
}

void main() async {
  late AtClient mockAtClient;
  late AtClientManager mockAtClientManager;
  late NotificationServiceImpl mockNotificationService;
  late RemoteSecondary mockRemoteSecondary;
  late SyncServiceImpl syncServiceImpl;

  setUpAll(() => registerFallbackValue(AtKey()));

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

  // Restores unit coverage lost when sync_new_test.dart was deleted in the
  // commit-log-free migration. Both targets are still live in
  // sync_service_impl.dart (the matcher in _setConflictInfo; the cursor on the
  // initial-sync pull path) and were otherwise untested on this branch.
  group('encryptedSharedKeyMatcher (reserved shared_key exclusion)', () {
    test('invalid shared_key key shapes do NOT match', () {
      final m = syncServiceImpl.encryptedSharedKeyMatcher;
      expect(m.hasMatch('shared_keyyy.alice@alice'), false);
      expect(m.hasMatch('sssshared_key.alice@alice'), false);
      expect(m.hasMatch('shared_key@alice'), false);
      expect(m.hasMatch('@alice:ssssshared_key@alice'), false);
      expect(m.hasMatch('@ssssssshared_key:phone.wavi@alice'), false);
      expect(m.hasMatch('@alice:shared_key.alice@alice'), false);
    });

    test('valid shared_key keys match', () {
      final m = syncServiceImpl.encryptedSharedKeyMatcher;
      expect(m.hasMatch('shared_key.alice@alice'), true);
      expect(m.hasMatch('@bob:shared_key@alice'), true);
    });
  });

  group('setAndGetSkipDeletesUntil (initial-sync delete guard)', () {
    test('localCommitId == -1: persists and returns the server commit id',
        () async {
      when(() => mockAtClient.put(any(that: SkipDeletesUntilMatcher()), any()))
          .thenAnswer((_) async => true);
      final result = await syncServiceImpl.setAndGetSkipDeletesUntil(-1, 100);
      expect(result, 100);
    });

    test('localCommitId > -1: returns the stored value', () async {
      when(() => mockAtClient.get(any(that: SkipDeletesUntilMatcher())))
          .thenAnswer((_) async => AtValue()..value = '40');
      final result = await syncServiceImpl.setAndGetSkipDeletesUntil(25, 100);
      expect(result, 40);
    });

    test('localCommitId > -1, nothing stored: returns null', () async {
      when(() => mockAtClient.get(any(that: SkipDeletesUntilMatcher())))
          .thenThrow(AtKeyNotFoundException('not found'));
      final result = await syncServiceImpl.setAndGetSkipDeletesUntil(25, 100);
      expect(result, null);
    });
  });
}
