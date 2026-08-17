import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

// NOTE: this file previously also held four mock-driven tests for the
// server→client pull path, server-timeout error chaining, invalid-batch
// JSON handling, and mid-sync stop(). All four mocked the (now removed)
// commit-log push path and were already `skip:`-marked obsolete; they
// are retired here. The equivalent behaviour is exercised end-to-end by
// `tests/at_functional_test/test/atclient_sync_test.dart` and
// `atclient_sync_conflict_test.dart`. The queue-based push path has unit
// coverage in `local_secondary_sync_queue_test.dart`.

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
      // ⚠️ The named argument belongs in the matcher. Without it the stub does
      // not match, mocktail returns null, and the write fails — which the
      // guard inside `setAndGetSkipDeletesUntil` swallows, so this test would
      // report 100 and pass while persisting nothing. Hence the `verify`.
      when(() => mockAtClient.put(any(that: SkipDeletesUntilMatcher()), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);

      final result = await syncServiceImpl.setAndGetSkipDeletesUntil(-1, 100);

      expect(result, 100);
      final captured = verify(() => mockAtClient.put(
              any(that: SkipDeletesUntilMatcher()), captureAny(),
              putRequestOptions: captureAny(named: 'putRequestOptions')))
          .captured;
      expect(captured[0], '100',
          reason: 'the value returned must be the value written, or a caller '
              'proceeds believing a window it never persisted');
      expect((captured[1] as PutRequestOptions).shouldEncrypt, isFalse,
          reason: 'a local: watermark is never synced and the keystore already '
              'encrypts at rest; routing it through the shared-data crypto '
              'path is what made it refusable in the first place');
    });

    test('a write that fails does not stop the first sync', () async {
      when(() => mockAtClient.put(any(that: SkipDeletesUntilMatcher()), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenThrow(AtKeyException('keystore unavailable'));

      // Best-effort: this run still has its window in hand, so it proceeds.
      await expectLater(
          syncServiceImpl.setAndGetSkipDeletesUntil(-1, 100), completion(100),
          reason: 'an unwritable watermark must not be able to stop a new '
              'client syncing for the first time');
      verify(() => mockAtClient.put(any(that: SkipDeletesUntilMatcher()), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).called(1);
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

  /// Its only caller runs it inside a `finally`, where anything thrown REPLACES
  /// the exception already in flight from the sync — so a failure to write the
  /// cursor would be reported in place of whatever actually broke the sync.
  /// "Never throws" is therefore the property to hold it to; if it cannot
  /// throw, it cannot mask.
  group('persistPullCursor (never throws, so it can never mask)', () {
    AtKey pullCursor() => AtKey.local('lastreceivedservercommitid', '@alice')
        .build();

    test('writes the cursor unencrypted', () async {
      when(() => mockAtClient.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer(
          (_) async => true);

      await syncServiceImpl.persistPullCursor(42);

      final captured = verify(() => mockAtClient.put(captureAny(), captureAny(),
              putRequestOptions: captureAny(named: 'putRequestOptions')))
          .captured;
      expect((captured[0] as AtKey).toString(), pullCursor().toString());
      expect(captured[1], '42');
      expect((captured[2] as PutRequestOptions).shouldEncrypt, isFalse);
    });

    test('swallows a write failure instead of replacing the sync error',
        () async {
      when(() => mockAtClient.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenThrow(AtKeyException('keystore unavailable'));

      await expectLater(syncServiceImpl.persistPullCursor(42), completes,
          reason: 'a throw here runs in a finally and would replace the '
              'in-flight exception, reporting a cursor-write failure as the '
              'reason a sync failed and losing the real cause');
    });
  });
}
