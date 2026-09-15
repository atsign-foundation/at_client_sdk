import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtData, AtKeyValueStore, AtMetaData;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// A muxable whose start waits until it is released or closed, so a stop can
/// land while the monitor is starting.
class _GatedMuxable extends Fake implements AtLookupMuxable {
  final Completer<void> startGate = Completer<void>();
  final List<String> calls = [];

  _GatedMuxable() {
    // NOTE: a muxable never started has nobody awaiting the gate its close
    // fails.
    startGate.future.ignore();
  }

  @override
  Stream<String> get notifications => const Stream.empty();

  @override
  Stream<bool> get notificationConnectionUp => const Stream.empty();

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {
    calls.add('start');
    await startGate.future;
  }

  /// Takes real time, as closing a socket does, so a close that did not wait
  /// for the teardown returns before this is recorded.
  @override
  Future<void> stopNotifications() async {
    await Future.delayed(const Duration(milliseconds: 50));
    calls.add('stopNotifications');
  }

  @override
  Future<void> close() async {
    calls.add('close');
    if (!startGate.isCompleted) {
      startGate.completeError(StoppedException('the lookup is closed'));
    }
  }
}

/// A keystore whose next-expiry answer waits for [_gate] and then fails the
/// way a store closed underneath it does.
class _GatedExpiryStore extends Fake
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  final Future<void> _gate;

  _GatedExpiryStore(this._gate);

  @override
  Future<DateTime?> nextExpiresAt() async {
    await _gate;
    throw StateError('Box has already been closed.');
  }

  @override
  Future<DateTime?> nextAvailableAt({DateTime? asOf}) async {
    await _gate;
    throw StateError('Box has already been closed.');
  }
}

/// What `stop()` ends, and what a caller still holding a stopped client's
/// parts is told.
void main() {
  final recorded = RecordedLogs();

  setUpAll(() {
    recorded.installOn(level: 'finer');
    registerFallbackValue(_FakeVerbBuilder());
    registerFallbackValue(AtKey());
  });

  group('AtConnection', () {
    test('after close, an attempt answers stopped without trying', () async {
      var tries = 0;
      final connection = AtConnection(
          atSign: '@stopped',
          attempt: (_) async {
            tries++;
            return AtConnectionState.online();
          });
      await connection.close();

      final state = await connection.attempt();

      expect(state.cause, AtConnectionCause.stopped);
      expect(tries, 0, reason: 'a stopped client has no connection to try');
    });

    test('a close during awaitOnline ends the wait at once', () async {
      final connection = AtConnection(
          atSign: '@waiting',
          attempt: (_) async =>
              AtConnectionState.offline(AtConnectionCause.unreachable));
      final waited = Stopwatch()..start();
      final waiting = connection.awaitOnline(
          budget: const Duration(seconds: 30),
          retryInterval: const Duration(seconds: 10));
      await Future.delayed(const Duration(milliseconds: 100));

      await connection.close();
      final state = await waiting.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('the wait sat out its retry interval'));

      expect(state.cause, AtConnectionCause.stopped);
      expect(waited.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('Monitor.close', () {
    Monitor monitorOn(AtLookupMuxable lookUp) => Monitor(
          atSign: '@monitor',
          atClientPreference: AtClientPreference(),
          lookUp: lookUp,
          handleNotification: (_) async {},
          getLastNotificationTime: () async => null,
        );

    test('ends a start in flight and returns once the teardown has run',
        () async {
      final lookUp = _GatedMuxable();
      final monitor = monitorOn(lookUp);
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(lookUp.calls, ['start']);

      await monitor.close().timeout(const Duration(seconds: 5),
          onTimeout: () => fail('close waited on the start it should end'));

      expect(lookUp.calls, ['start', 'close', 'stopNotifications'],
          reason: 'the lookup is closed first, so the start fails at once, '
              'and the teardown has run by the time close returns');
      expect(() => monitor.start(), throwsA(isA<StoppedException>()));
    });
  });

  group('NotificationServiceImpl', () {
    late MockAtClientImpl atClient;

    setUp(() {
      atClient = MockAtClientImpl();
      when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => atClient.atSign).thenReturn(Atsign('@alice'));
      when(() => atClient.enrollmentId).thenReturn(null);
      when(() => atClient.atChops).thenReturn(MockAtChops());
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
        ..namespace = 'wavi'
        ..monitorAutoStart = false);
    });

    Future<NotificationServiceImpl> service(AtLookupMuxable lookUp) async {
      final finder = MockSecondaryAddressFinder();
      when(() => finder.findSecondary(any()))
          .thenAnswer((_) async => SecondaryAddress('bob.example', 1));
      return await NotificationServiceImpl.create(atClient,
          monitor: Monitor(
            atSign: '@alice',
            atClientPreference: AtClientPreference(),
            lookUp: lookUp,
            handleNotification: (_) async {},
            getLastNotificationTime: () async => null,
          ),
          secondaryAddressFinder: finder) as NotificationServiceImpl;
    }

    test('stop returns once the monitor\'s connection is closed', () async {
      final lookUp = _GatedMuxable();
      final notifications = await service(lookUp);
      notifications.startListening();
      await Future.delayed(const Duration(milliseconds: 20));

      await notifications.stop();

      expect(lookUp.calls, containsAllInOrder(['close', 'stopNotifications']));
    });

    test('refuses a subscription or a start after stop', () async {
      final notifications = await service(_GatedMuxable());
      await notifications.stop();

      expect(() => notifications.subscribe(regex: '.*'),
          throwsA(isA<StoppedException>()));
      expect(() => notifications.subscribeFiltered(namespace: 'wavi'),
          throwsA(isA<StoppedException>()));
      expect(() => notifications.startListening(),
          throwsA(isA<StoppedException>()));
    });

    test('a status poll between checks ends as soon as the service stops',
        () async {
      final remote = MockRemoteSecondary();
      when(() => atClient.getRemoteSecondary()).thenReturn(remote);
      when(() => remote.executeVerb(any())).thenAnswer((_) async => 'data:n1');
      when(() => atClient.notifyStatus(any()))
          .thenAnswer((_) async => 'data:queued');
      final notifications = await service(_GatedMuxable());
      final pending = notifications.notify(NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@alice')
                ..sharedWith('@bob'))
              .build()));
      // Past the first check, into a two-second pause.
      await Future.delayed(const Duration(milliseconds: 700));
      final stopped = Stopwatch()..start();

      await notifications.stop();
      await pending;

      expect(stopped.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'the pause is cut short by the stop, so nothing is left '
              'waiting to ask a closed connection');
    });
  });

  group('SyncServiceImpl.close', () {
    test('leaves a remote it was handed open, and cannot be started again',
        () async {
      final atClient = MockAtClientImpl();
      final remote = MockRemoteSecondary();
      final notifications = MockNotificationService();
      when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => atClient.enrollmentId).thenReturn(null);
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
      when(() => atClient.notificationService).thenReturn(notifications);
      when(() => notifications.subscribe(
              regex: any(named: 'regex'),
              shouldDecrypt: any(named: 'shouldDecrypt')))
          .thenAnswer((_) => const Stream.empty());
      final sync = await SyncServiceImpl.create(atClient,
          remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
      final caughtUp = expectLater(
          sync.waitUntilCaughtUp(), throwsA(isA<StoppedException>()),
          reason: 'a caller waiting to catch up is told the service stopped, '
              'rather than waiting for ever on events that will not come');

      await sync.close();

      verifyNever(() => remote.closeConnection());
      await caughtUp;
      await expectLater(sync.start(), throwsA(isA<StoppedException>()));
    });
  });

  group('AtCollection', () {
    test('ends when every source it reads has ended, and its scheduler with it',
        () async {
      final notifications = StreamController<AtNotification>.broadcast();
      final dataEvents = StreamController<DataEvent>.broadcast();
      final atClient = MockAtClientImpl();
      when(() => atClient.atSign).thenReturn(Atsign('@alice'));
      final collection = collectionWithInjectedBoth<Map<String, dynamic>>(
          atClient, 'things.wavi', const Duration(days: 1),
          notifications: notifications.stream, dataEvents: dataEvents.stream);
      collection.availableEvents;
      final watched = expectLater(collection.watch(), emitsDone);

      await notifications.close();
      await Future.delayed(Duration.zero);
      expect(collection.hasEnded, isFalse,
          reason: 'its data events can still reach it');
      await dataEvents.close();
      await watched;

      expect(collection.hasEnded, isTrue);
      expect(collection.availableSchedulerStopped, isTrue,
          reason: 'its timer would otherwise outlive the client');
    });
  });

  group('AtClientImpl.stop', () {
    late Directory dir;
    late List<MockAtLookupImpl> built;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('client_stop_');
      built = [];
      AtClientManager.getInstance().reset();
    });

    tearDown(() async {
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      AtClientManager.getInstance().reset();
      dir.deleteSync(recursive: true);
    });

    AtLookupMuxable recording({
      required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder,
      Map<String, dynamic> clientConfig = const {},
    }) {
      final lookUp = MockAtLookupImpl();
      when(() => lookUp.isConnectionAvailable()).thenReturn(false);
      when(() => lookUp.close()).thenAnswer((_) async {});
      when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
      // the bridge reads the enrollment id off the lookup until the ladder goes
      // ignore: deprecated_member_use
      when(() => lookUp.enrollmentId).thenReturn(null);
      when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((_) async => 'data:null');
      built.add(lookUp);
      return lookUp;
    }

    Future<AtClientImpl> client(String atSign) async => await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: AtClientPreference()
          ..hiveStoragePath = dir.path
          ..namespace = 'wavi'
          ..monitorAutoStart = false,
        lookUps: recording) as AtClientImpl;

    test('closes every connection it opened: its own, sync\'s, the monitor\'s',
        () async {
      final stopping = await client('@closesall');
      expect(built, hasLength(3));

      await stopping.stop();

      for (final lookUp in built) {
        verify(() => lookUp.close()).called(1);
      }
    });

    test('closes services a setter replaced, and waits for them', () async {
      final running = await client('@replaced');
      running.syncService =
          await SyncServiceImpl.create(running, warmStartSync: false);
      running.notificationService = await NotificationServiceImpl.create(
          running,
          lookUps: running.lookUps,
          secondaryAddressFinder: running.secondaryAddressFinder);
      expect(built, hasLength(5));

      await running.stop();

      for (final lookUp in built) {
        verify(() => lookUp.close()).called(1);
      }
    });

    test('ends a collection it built, and the collection\'s scheduler',
        () async {
      final running = await client('@collects');
      final collection = await running.collection<Map<String, dynamic>>(
          'things.wavi', const Duration(days: 1));
      collection.availableEvents;
      expect(collection.availableSchedulerStopped, isFalse);

      await running.stop();
      await Future.delayed(Duration.zero);

      expect(collection.hasEnded, isTrue);
      expect(collection.availableSchedulerStopped, isTrue);
    });

    test('ends a secret wait still in flight', () async {
      final running = await client('@waits');
      final wait = expectLater(
          AtClientSecretSharing.forClient(running).waitForSecret(
              'wavi', 'never',
              timeout: const Duration(minutes: 5)),
          throwsA(isA<StoppedException>()));

      await running.stop();

      await wait.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('the wait outlived the client'));
    });

    test('a sweep that runs on past the stop ends quietly', () async {
      final stopping = await client('@sweeps');
      await stopping.stop();
      recorded.records.clear();

      await stopping.expirySweepForTest();
      await stopping.availabilitySweepForTest();

      expect(
          recorded.at('WARNING'),
          containsAll([
            'Abandoned the expiry sweep: the client stopped',
            'Abandoned the availability sweep: the client stopped',
          ]),
          reason: 'each abandoned sweep says so, once');
      expect(recorded.at('WARNING'), isNot(contains(contains('failed'))),
          reason: 'the store is gone because the client stopped; that is not '
              'a failed sweep');
      expect(recorded.records.map((r) => r.message),
          isNot(contains(contains('#0'))),
          reason: 'a stop is logged without a stack trace');
    });

    test('a stop landing while a keystore timer is re-armed ends the arm',
        () async {
      final stopping = await client('@rearms');
      final gate = Completer<void>();
      stopping.localSecondary!.keyStore = _GatedExpiryStore(gate.future);
      final arming = Future.wait([
        stopping.armExpiryTimerForTest(),
        stopping.armAvailableTimerForTest(),
      ]);

      await stopping.stop();
      gate.complete();

      await expectLater(arming, completes,
          reason: 'the store closed under the await because the client '
              'stopped, and a timer callback has nobody to hand that to');
    });

    test('a local operation after stop is refused as stopped', () async {
      final stopping = await client('@localafter');
      final key =
          AtKey.local('phone', '@localafter', namespace: 'wavi').build();
      await stopping.put(key, '123');

      await stopping.stop();

      await expectLater(stopping.get(key), throwsA(isA<StoppedException>()),
          reason: 'the store is released, so what the caller learns is that '
              'the client stopped, not that a storage box is missing');
      await expectLater(
          stopping.put(key, '456'), throwsA(isA<StoppedException>()));
    });
  });
}
