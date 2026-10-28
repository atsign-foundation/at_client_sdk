import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/hive_store.dart';
import 'test_utils/no_keys.dart';

AtClientPreference _createPreference(String storagePath) =>
    AtClientPreference()..hiveStoragePath = 'test/hive/$storagePath';

Future<AtClient> _buildAtClient(String atSign) => buildAtClient(
      atSign: atSign,
      namespace: 'test',
      preference: _createPreference(atSign.replaceAll('@', '')),
      atKeysIo: noKeysFor(atSign),
      storage:
          hiveStoreFor(atSign, _createPreference(atSign.replaceAll('@', ''))),
    );

void main() {
  tearDown(() async {
    final activeInstances = List<AtClient>.from(
      AtClientImpl.atClientInstanceMap.values,
    );
    for (var client in activeInstances) {
      await (client as AtClientImpl).stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  group('validate stop() behaviour', () {
    group('Client termination tests', () {
      test(
        'stop() is idempotent, releases storage, and removes the client from '
        'the instance map',
        () async {
          final atSign = '@stop_integration';
          final atClient = await AtClientImpl.create(
            atSign,
            'test',
            _createPreference('stop_integration'),
            atKeysIo: noKeysFor(atSign),
            storage:
                hiveStoreFor(atSign, _createPreference('stop_integration')),
          ) as AtClientImpl;

          expect(AtClientImpl.atClientInstanceMap.containsKey(atSign), true);
          final storage = atClient.storage as AtClientStorageBase;
          expect(storage.isAttached, isTrue);

          await atClient.stop();
          await atClient.stop();
          await atClient.stop();

          expect(AtClientImpl.atClientInstanceMap.containsKey(atSign), false,
              reason: 'a stopped client keeps nothing open, so nothing should '
                  'hand it back; a later create() builds a fresh one');
          expect(storage.isAttached, isFalse,
              reason: 'stop() drops the claim on the storage it built');
          expect(atClient.isStopped, true);
          expect(() => atClient.start(), throwsA(isA<StateError>()),
              reason: 'a client whose storage is released cannot be restarted');
        },
      );

      test(
        'close() should handle errors gracefully and continue cleanup',
        () async {
          final atSign = '@stop_errors';
          final mockRemoteSecondary = MockRemoteSecondary();

          when(
            () => mockRemoteSecondary.closeConnection(),
          ).thenThrow(Exception('Connection close error'));

          final atClient = await AtClientImpl.create(
            atSign,
            'test',
            _createPreference('stop_errors'),
            atKeysIo: noKeysFor(atSign),
            remoteSecondary: mockRemoteSecondary,
            storage: hiveStoreFor(atSign, _createPreference('stop_errors')),
          ) as AtClientImpl;
          await atClient.stop();
          expect(atClient.isStopped, true);
          expect(AtClientImpl.atClientInstanceMap.containsKey(atSign), false,
              reason: 'a failure closing the connection must not leave the '
                  'client registered as live');
        },
      );

      test('closeConnection() stops the RemoteSecondary\'s lookup', () async {
        final mockAtLookup = MockAtLookUp();
        bool calledFlag = false;
        when(() => mockAtLookup.stop()).thenAnswer((_) async {
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
      late MockAtLookUp mockAtLookup;
      late _StubMuxable stubMuxable;

      setUp(() {
        mockAtLookup = MockAtLookUp();
        stubMuxable = _StubMuxable();
        when(() => mockAtLookup.close()).thenAnswer((_) async => {});

        monitor = Monitor(
          atSign: '@test',
          atClientPreference: AtClientPreference(),
          lookUp: stubMuxable,
          handleNotification: (String jsonEncoded) async {},
          getLastNotificationTime: () async => null,
        );
      });

      test(
        'stop() should set targetState to notConnected and be idempotent',
        () async {
          monitor.start();
          await Future.delayed(Duration(milliseconds: 10));
          monitor.stop();
          expect(monitor.targetState, NotificationListenerState.notConnected);

          monitor.stop();
          expect(monitor.targetState, NotificationListenerState.notConnected);
        },
      );

      test('stop() should emit notConnected as final state', () async {
        final stateHistory = <NotificationListenerState>[];
        final subscription = monitor.currentStateStream.listen(
          stateHistory.add,
        );

        monitor.start();
        await Future.delayed(Duration(milliseconds: 10));
        monitor.stop();
        await Future.delayed(Duration(milliseconds: 10));

        expect(
          stateHistory.last,
          NotificationListenerState.notConnected,
          reason: 'Monitor should end in notConnected state after stop()',
        );
        await subscription.cancel();
      });
    });

    group('Rebuilding a stopped client', () {
      test(
        'building the same atSign after stop() creates a new instance',
        () async {
          final atSign = '@test_same_atsign_close';

          final atClient1 = await _buildAtClient(atSign);
          await atClient1.stop();
          final atClient2 = await _buildAtClient(atSign);
          expect(identical(atClient1, atClient2), false,
              reason: 'the stopped client released its storage; a new one is '
                  'built and wired');

          expect((atClient2.syncService as SyncServiceImpl).isStopped, false);
          expect(
            (atClient2.notificationService as NotificationServiceImpl)
                .isStopped,
            false,
          );
        },
      );
    });
  });
}

/// Stands in for the muxable the Monitor now drives, so these tests exercise
/// Monitor's own state handling rather than a socket.
class _StubMuxable extends Fake implements AtLookupMuxable {
  final _notifications = StreamController<String>.broadcast();
  final _up = StreamController<bool>.broadcast();

  @override
  Stream<String> get notifications => _notifications.stream;

  @override
  Stream<bool> get notificationConnectionUp => _up.stream;

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async =>
      _up.add(true);

  @override
  Future<void> stopNotifications() async => _up.add(false);
}
