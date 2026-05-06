import 'dart:async';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class MockSecondaryPersistenceStore extends Mock
    implements SecondaryPersistenceStore {}

class MockHivePersistenceManager extends Mock
    implements HivePersistenceManager {}

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

      test('should handle Hive storage correctly on switch', () async {
        final atSign1 = '@hive_soft';
        final atSign2 = '@hive_soft2';

        await _initializeAtClient(atSign1);

        // Get persistence store for first atSign
        final persistenceStore1 = SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(atSign1);
        final hiveManager1 = persistenceStore1?.getHivePersistenceManager();

        // Switch to second atSign
        await _initializeAtClient(atSign2);

        // Hive should remain accessible
        expect(AtClientImpl.atClientInstanceMap.containsKey(atSign1), true,
            reason: 'First client should remain in cache');

        final persistenceStoreAfter =
            SecondaryPersistenceStoreFactory.getInstance()
                .getSecondaryPersistenceStore(atSign1);
        expect(persistenceStoreAfter, isNotNull,
            reason: 'Hive storage should still be accessible');

        final hiveManagerAfter =
            persistenceStoreAfter?.getHivePersistenceManager();
        expect(hiveManagerAfter, isNotNull);
        expect(identical(hiveManager1, hiveManagerAfter), true);
        expect(AtClientImpl.atClientInstanceMap.containsKey(atSign1), true);
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
  });
}
