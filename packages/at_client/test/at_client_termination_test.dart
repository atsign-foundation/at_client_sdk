import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

AtClientPreference _createPreference(String storagePath) => AtClientPreference()
  ..hiveStoragePath = 'test/hive/$storagePath'
  ..commitLogPath = 'test/hive/$storagePath';

Future<AtClient> _initializeAtClient(String atSign) async {
  final atClientManager = AtClientManager.getInstance();
  await atClientManager.setCurrentAtSign(
    atSign,
    'test',
    _createPreference(atSign.replaceAll('@', '')),
  );
  return atClientManager.atClient;
}

void main() {
  setUpAll(() => registerFallbackValue(StatsVerbBuilder()));

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
            remoteSecondary: mockRemoteSecondary,
          ) as AtClientImpl;
          await atClient.stop();
          expect(atClient.isStopped, true);
          expect(AtClientImpl.atClientInstanceMap.containsKey(atSign), false,
              reason: 'a failure closing the connection must not leave the '
                  'client registered as live');
        },
      );

      test('work that resumes while stop() runs opens no new connection',
          () async {
        final mockAtLookup = MockAtLookUp();
        when(() => mockAtLookup.close()).thenAnswer((_) async {});
        final remoteSecondary = RemoteSecondary(
            '@stop_window', _createPreference('stop_window'),
            atLookUp: mockAtLookup);
        final atClient = await AtClientImpl.create(
          '@stop_window',
          'test',
          _createPreference('stop_window'),
          remoteSecondary: remoteSecondary,
        ) as AtClientImpl;

        // NOTE: the connection state reports `stopped` as the stop's first
        // step, while the services and the remote are still to be stopped.
        final outcome = Completer<Object?>();
        atClient.connection.changes.listen((state) {
          if (state.cause != AtConnectionCause.stopped) return;
          remoteSecondary
              .executeCommand('llookup:k@stop_window\n', auth: true)
              .then((_) => outcome.complete('reached the atServer'),
                  onError: outcome.complete);
        });

        await atClient.stop();

        expect(await outcome.future, isA<AtClientStoppedException>());
        verifyNever(
            () => mockAtLookup.executeCommand(any(), auth: any(named: 'auth')));
      });

      test(
          'a stopping remote secondary refuses new connections on the lookup '
          'it built, and leaves an injected one alone', () async {
        final owned = _MockMuxable();
        final built = RemoteSecondary('@owned', AtClientPreference(),
            lookUps: _lookUpsReturning(owned));
        built.refuseNewWork();
        verify(() => owned.refuseNewConnections()).called(1);

        final injected = _MockMuxable();
        final given = RemoteSecondary('@injected', AtClientPreference(),
            atLookUp: injected);
        given.refuseNewWork();
        verifyNever(() => injected.refuseNewConnections());
      });

      test(
          'a request that was waiting when the stop began ends as stopped, not '
          'as a failed connection', () async {
        final owned = _MockMuxable();
        final gate = Completer<void>();
        when(() => owned.executeCommand(any(), auth: any(named: 'auth')))
            .thenAnswer((_) async {
          await gate.future;
          throw ConnectionInvalidException('no new connection');
        });
        final remoteSecondary = RemoteSecondary(
            '@waiting', AtClientPreference(),
            lookUps: _lookUpsReturning(owned));

        final running =
            remoteSecondary.executeCommand('llookup:k@waiting\n', auth: true);
        remoteSecondary.refuseNewWork();
        gate.complete();

        await expectLater(running, throwsA(isA<AtClientStoppedException>()));
      });

      test('control: the same failure without a stop is the connection failure',
          () async {
        final owned = _MockMuxable();
        when(() => owned.executeCommand(any(), auth: any(named: 'auth')))
            .thenThrow(ConnectionInvalidException('no new connection'));
        final remoteSecondary = RemoteSecondary('@live', AtClientPreference(),
            lookUps: _lookUpsReturning(owned));

        await expectLater(
            remoteSecondary.executeCommand('llookup:k@live\n', auth: true),
            throwsA(isA<ConnectionInvalidException>()));
      });

      test('close() should close RemoteSecondary connection', () async {
        final mockAtLookup = MockAtLookUp();
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

      test('a remote secondary whose connection stop() closed opens no new one',
          () async {
        final mockAtLookup = MockAtLookUp();
        when(() => mockAtLookup.close()).thenAnswer((_) async {});
        final remoteSecondary = RemoteSecondary(
          '@test',
          AtClientPreference(),
          atLookUp: mockAtLookup,
        );
        await remoteSecondary.executeCommand('llookup:k@test\n', auth: true);
        verify(() => mockAtLookup.executeCommand(any(), auth: true)).called(1);

        await remoteSecondary.closeConnection();

        await expectLater(
            remoteSecondary.executeCommand('llookup:k@test\n', auth: true),
            throwsA(isA<AtClientStoppedException>()));
        await expectLater(remoteSecondary.executeVerb(StatsVerbBuilder()),
            throwsA(isA<AtClientStoppedException>()));
        await expectLater(
            remoteSecondary.sync(0), throwsA(isA<AtClientStoppedException>()));
        verifyNever(
            () => mockAtLookup.executeCommand(any(), auth: any(named: 'auth')));
        verifyNever(() => mockAtLookup.executeVerb(any()));
        expect(() => remoteSecondary.atLookUp,
            throwsA(isA<AtClientStoppedException>()),
            reason: 'a caller holding the lookup would open a connection '
                'for the stopped client itself');
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

    group('AtSign switching tests', () {
      test('should maintain correct client instances in map', () async {
        final firstAtSign = '@alice_switch';
        final secondAtSign = '@bob_switch';

        final atClient1 =
            await _initializeAtClient(firstAtSign) as AtClientImpl;
        expect(AtClientImpl.atClientInstanceMap.containsKey(firstAtSign), true);

        await _initializeAtClient(secondAtSign);
        expect(AtClientImpl.atClientInstanceMap.containsKey(firstAtSign), false,
            reason: 'switching away stops the outgoing client, and a stopped '
                'client releases its storage and leaves the map');
        expect(
          AtClientImpl.atClientInstanceMap.containsKey(secondAtSign),
          true,
        );
        expect(atClient1.isStopped, true);
        final rebuilt = await _initializeAtClient(firstAtSign);
        expect(identical(atClient1, rebuilt), false,
            reason: 'switching back opens storage afresh on a new client');
        expect(rebuilt.isStopped, false);
      });

      test('switching to same atSign should handle correctly', () async {
        final atSign = '@test_same_atsign';

        // init both atClients with same atSign
        final atClient1 = await _initializeAtClient(atSign);
        final atClient2 = await _initializeAtClient(atSign);

        // AtClientImpl.create() caches by default regardless of useClientCaching
        // useClientCaching only affects behavior on atSign SWITCH, not create()
        // So without close() between calls, both modes return the same instance
        expect(
          identical(atClient1, atClient2),
          true,
          reason:
              'create() returns cached instance when not closed between calls',
        );
      });

      test(
        'switching to same atSign after close should create new instance',
        () async {
          final atSign = '@test_same_atsign_close';

          final atClient1 = await _initializeAtClient(atSign);
          await atClient1.stop();
          final atClient2 = await _initializeAtClient(atSign);
          expect(identical(atClient1, atClient2), false,
              reason: 'the stopped client released its storage; the manager '
                  'builds and wires a new one');

          expect((atClient2.syncService as SyncServiceImpl).isStopped, false);
          expect(
            (atClient2.notificationService as NotificationServiceImpl)
                .isStopped,
            false,
          );
        },
      );
    });

    group('setCurrentAtSign idempotency', () {
      // The same-atSign short-circuit added with the
      // bypasscache_test flake fix. Forced-reset cases (callers
      // passing atChops / atLookUp / enrollmentId, or an explicitly
      // stopped atClient) must still recreate; bare no-arg calls
      // must reuse.

      test(
        'same-atSign, no override args → identical syncService preserved',
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
          expect(
            identical(atClient1, atClient2),
            true,
            reason: 'idempotent setCurrentAtSign returns same atClient',
          );
          expect(
            identical(syncService1, atClient2.syncService),
            true,
            reason: 'syncService is preserved across idempotent calls',
          );
          expect(
            (atClient2.syncService as SyncServiceImpl).isStopped,
            false,
            reason: 'preserved syncService is not stopped',
          );
        },
      );

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
        expect(
          identical(syncService1, atClient2.syncService),
          false,
          reason: 'atChops override forces syncService recreate',
        );
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
        expect(
          identical(syncService1, atClient2.syncService),
          false,
          reason: 'enrollmentId override forces syncService recreate',
        );
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
        expect(
          events,
          isEmpty,
          reason: 'no SwitchAtSignEvent on idempotent setCurrentAtSign',
        );

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

class _MockMuxable extends Mock implements AtLookupMuxable {}

/// A lookup factory that hands back [lookUp], as a client's own factory hands
/// back the lookup it builds.
AtLookUpFactory _lookUpsReturning(AtLookupMuxable lookUp) => (
        {required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
        Map<String, dynamic> clientConfig = const {}}) =>
    lookUp;

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
