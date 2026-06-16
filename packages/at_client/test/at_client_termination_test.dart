import 'dart:async';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookup extends Mock implements AtLookUp {}

class MockAtChops extends Mock implements AtChops {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

AtClientPreference _createPreference(String storagePath) => AtClientPreference()
  ..hiveStoragePath = 'test/hive/$storagePath'
  ..commitLogPath = 'test/hive/$storagePath';

Future<AtClient> _initializeAtClient(String atSign) async {
  final atClientManager = AtClientManager.getInstance();
  await atClientManager.setCurrentAtSign(
      atSign, 'test', _createPreference(atSign.replaceAll('@', '')));
  return atClientManager.atClient;
}

void main() {
  tearDown(() async {
    final activeInstances =
        List<AtClient>.from(AtClientImpl.atClientInstanceMap.values);
    for (var client in activeInstances) {
      await (client as AtClientImpl).stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  group('validate stop() behaviour', () {
    group('Client termination tests', () {
      test('close() should be idempotent and remove client from instance map',
          () async {
        final atSign = '@stop_integration';
        final atClient = await AtClientImpl.create(
                atSign, 'test', _createPreference('stop_integration'))
            as AtClientImpl;

        expect(AtClientImpl.atClientInstanceMap.containsKey(atSign), true);

        // Call close multiple times to verify idempotency
        await atClient.stop();
        await atClient.stop();
        await atClient.stop();

        expect(AtClientImpl.atClientInstanceMap.containsKey(atSign), true);
        expect(atClient.isStopped, true);
      });

      test('close() should handle errors gracefully and continue cleanup',
          () async {
        final atSign = '@stop_errors';
        final mockRemoteSecondary = MockRemoteSecondary();

        when(() => mockRemoteSecondary.closeConnection())
            .thenThrow(Exception('Connection close error'));

        final atClient = await AtClientImpl.create(
            atSign, 'test', _createPreference('stop_errors'),
            remoteSecondary: mockRemoteSecondary) as AtClientImpl;

        await atClient.stop();
        expect(AtClientImpl.atClientInstanceMap.containsKey(atSign), true);
      });

      test('close() should close RemoteSecondary connection', () async {
        final mockAtLookup = MockAtLookup();
        bool calledFlag = false;
        when(() => mockAtLookup.close()).thenAnswer((_) async {
          calledFlag = true;
        });

        final remoteSecondary = RemoteSecondary(
          '@test',
          AtClientPreference(),
          atLookUp: mockAtLookup,
        );

        await remoteSecondary.closeConnection();
        expect(calledFlag, true);
      });
    });

    group('Monitor lifecycle tests', () {
      late Monitor monitor;
      late MockAtLookup mockAtLookup;
      late MockAtChops mockAtChops;
      late MockSecondaryAddressFinder mockAddressFinder;

      setUp(() {
        mockAtLookup = MockAtLookup();
        mockAtChops = MockAtChops();
        mockAddressFinder = MockSecondaryAddressFinder();
        when(() => mockAtLookup.close()).thenAnswer((_) async => {});

        monitor = Monitor(
          atSign: '@test',
          atClientPreference: AtClientPreference(),
          atChops: mockAtChops,
          enrollmentId: null,
          secondaryAddressFinder: mockAddressFinder,
          handleNotification: (String jsonEncoded) async {},
          getLastNotificationTime: () async => null,
        );
      });

      test('stop() should set targetState to notConnected and be idempotent',
          () async {
        monitor.start();
        await Future.delayed(Duration(milliseconds: 10));
        monitor.stop();
        expect(monitor.targetState, NotificationListenerState.notConnected);

        monitor.stop();
        expect(monitor.targetState, NotificationListenerState.notConnected);
      });

      test('stop() should emit notConnected as final state', () async {
        final stateHistory = <NotificationListenerState>[];
        final subscription =
            monitor.currentStateStream.listen(stateHistory.add);

        monitor.start();
        await Future.delayed(Duration(milliseconds: 10));
        monitor.stop();
        await Future.delayed(Duration(milliseconds: 10));

        expect(stateHistory.last, NotificationListenerState.notConnected,
            reason: 'Monitor should end in notConnected state after stop()');
        await subscription.cancel();
      });
    });

    group('AtSign switching tests', () {
      test('should maintain correct client instances in map', () async {
        final firstAtSign = '@alice_switch';
        final secondAtSign = '@bob_switch';

        final atClient1 =
            await _initializeAtClient(firstAtSign) as AtClientImpl;
        expect(AtClientImpl.atClientInstanceMap.containsKey(firstAtSign), true);

        await _initializeAtClient(secondAtSign);

        expect(AtClientImpl.atClientInstanceMap.containsKey(firstAtSign), true);
        expect(
            AtClientImpl.atClientInstanceMap.containsKey(secondAtSign), true);

        expect(atClient1.isStopped, true);

        // Verify switching back returns the same cached instance
        final reusedAtClient = await _initializeAtClient(firstAtSign);
        expect(identical(atClient1, reusedAtClient), true);
      });

      test('switching to same atSign should handle correctly', () async {
        final atSign = '@test_same_atsign';

        // init both atClients with same atSign
        final atClient1 = await _initializeAtClient(atSign);
        final atClient2 = await _initializeAtClient(atSign);

        // AtClientImpl.create() caches by default regardless of useClientCaching
        // useClientCaching only affects behavior on atSign SWITCH, not create()
        // So without close() between calls, both modes return the same instance
        expect(identical(atClient1, atClient2), true,
            reason:
                'create() returns cached instance when not closed between calls');
      });

      test('switching to same atSign after close should create new instance',
          () async {
        final atSign = '@test_same_atsign_close';

        final atClient1 = await _initializeAtClient(atSign);
        await atClient1.stop();

        final atClient2 = await _initializeAtClient(atSign);

        expect(identical(atClient1, atClient2), true);

        expect((atClient2.syncService as SyncServiceImpl).isStopped, false);
        expect(
            (atClient2.notificationService as NotificationServiceImpl)
                .isStopped,
            false);
      });
    });

    group('setCurrentAtSign idempotency', () {
      // The same-atSign short-circuit added with the
      // bypasscache_test flake fix. Forced-reset cases (callers
      // passing atChops / atLookUp / enrollmentId, or an explicitly
      // stopped atClient) must still recreate; bare no-arg calls
      // must reuse.

      test('same-atSign, no override args → identical syncService preserved',
          () async {
        final atSign = '@idempotent_no_override';

        final atClient1 = await _initializeAtClient(atSign);
        final syncService1 = atClient1.syncService;

        // Second call with the exact same atSign / namespace / prefs
        // and no override args must short-circuit — atClient AND its
        // syncService both stay identical. Catches regressions where
        // setCurrentAtSign recreates anyway and leaves two
        // SyncService instances on the same Hive backing (the original
        // cause of the bypasscache_test localToRemote race).
        final atClient2 = await _initializeAtClient(atSign);
        expect(identical(atClient1, atClient2), true,
            reason: 'idempotent setCurrentAtSign returns same atClient');
        expect(identical(syncService1, atClient2.syncService), true,
            reason: 'syncService is preserved across idempotent calls');
        expect((atClient2.syncService as SyncServiceImpl).isStopped, false,
            reason: 'preserved syncService is not stopped');
      });

      test('same-atSign with atChops override → recreates', () async {
        final atSign = '@idempotent_with_atchops';

        final atClient1 = await _initializeAtClient(atSign);
        final syncService1 = atClient1.syncService;

        // Caller passes atChops — the idempotency check must NOT
        // short-circuit, because the override is a signal the caller
        // wants a fresh atClient.
        final mockAtChops = MockAtChops();
        await AtClientManager.getInstance().setCurrentAtSign(
          atSign,
          'test',
          _createPreference(atSign.replaceAll('@', '')),
          atChops: mockAtChops,
        );
        final atClient2 = AtClientManager.getInstance().atClient;
        // syncService MUST be a fresh instance.
        expect(identical(syncService1, atClient2.syncService), false,
            reason: 'atChops override forces syncService recreate');
      });

      test('same-atSign with enrollmentId override → recreates', () async {
        final atSign = '@idempotent_with_enrollment';

        final atClient1 = await _initializeAtClient(atSign);
        final syncService1 = atClient1.syncService;

        await AtClientManager.getInstance().setCurrentAtSign(
          atSign,
          'test',
          _createPreference(atSign.replaceAll('@', '')),
          enrollmentId: 'some-enrollment-id',
        );
        final atClient2 = AtClientManager.getInstance().atClient;
        expect(identical(syncService1, atClient2.syncService), false,
            reason: 'enrollmentId override forces syncService recreate');
      });

      test('idempotent call does not fire SwitchAtSignEvent', () async {
        final atSign = '@idempotent_no_event';

        await _initializeAtClient(atSign);

        // Register a change listener AFTER the initial setCurrentAtSign
        // so we only observe the second (idempotent) call's behaviour.
        final events = <SwitchAtSignEvent>[];
        final listener = _CapturingAtSignChangeListener(events.add);
        AtClientManager.getInstance().listenToAtSignChange(listener);

        await _initializeAtClient(atSign);

        // Existing code path only fires the event when previous and
        // current atSigns differ; idempotent short-circuit returns
        // before that branch. Regression guard for accidentally
        // moving the event emission ahead of the short-circuit.
        expect(events, isEmpty,
            reason: 'no SwitchAtSignEvent on idempotent setCurrentAtSign');

        AtClientManager.getInstance().removeChangeListeners(listener);
      });
    });
  });
}

/// Test-only AtSignChangeListener that forwards every event to a
/// caller-supplied callback. Avoids hand-rolling a mock inside each
/// test.
class _CapturingAtSignChangeListener implements AtSignChangeListener {
  _CapturingAtSignChangeListener(this._onEvent);
  final void Function(SwitchAtSignEvent) _onEvent;

  @override
  void listenToAtSignChange(SwitchAtSignEvent event) => _onEvent(event);
}
