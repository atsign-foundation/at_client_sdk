import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/sync/hive_box_sync_queue_store.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    hide AtNotification;
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/recorded_logs.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {}

class _MockAtClient extends Mock implements AtClient {}

class _MockLocalSecondary extends Mock implements LocalSecondary {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

void main() {
  final recorded = RecordedLogs();

  setUpAll(() {
    recorded.installOn(level: 'finer');
    registerFallbackValue(AtKey());
    registerFallbackValue(SyncVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  group('stop() during a round', () {
    late _MockAtClient atClient;
    late _MockLocalSecondary localSecondary;
    late _MockRemoteSecondary remote;
    late SyncServiceImpl sync;

    setUp(() async {
      recorded.records.clear();
      atClient = _MockAtClient();
      localSecondary = _MockLocalSecondary();
      remote = _MockRemoteSecondary();
      when(() => atClient.getCurrentAtSign()).thenReturn('@abandon');
      when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
      final notifications = _MockNotificationService();
      when(() => notifications.subscribe(
              regex: any(named: 'regex'),
              shouldDecrypt: any(named: 'shouldDecrypt')))
          .thenAnswer((_) => const Stream<AtNotification>.empty());
      when(() => atClient.notificationService).thenReturn(notifications);
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
      sync = await SyncServiceImpl.create(atClient,
          remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
    });

    /// A round with nothing persisted yet: no pull cursor, and every
    /// watermark write accepted.
    void stubFreshClient() {
      when(() => atClient.get(any()))
          .thenThrow(AtKeyNotFoundException('nothing persisted yet'));
      when(() => atClient.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => localSecondary.peekSyncQueue())
          .thenAnswer((_) async => <String>[]);
      when(() => localSecondary.isWriteInProgress(any())).thenReturn(false);
    }

    /// One entry the atServer hands back for the pull.
    String serverEntry(String atKey, {required String operation}) =>
        'data:${jsonEncode([
              {
                'atKey': atKey,
                'value': operation == '-' ? null : 'x',
                'metadata': null,
                'commitId': 5,
                'operation': operation,
              }
            ])}';

    test('a batch push the stop cuts short is abandoned, not logged as failed',
        () async {
      stubFreshClient();
      when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 1);
      when(() => localSecondary.peekSyncQueue(limit: any(named: 'limit')))
          .thenAnswer((_) async => ['k1.wavi@abandon']);
      when(() => localSecondary.readSyncQueueEntry(any())).thenAnswer(
          (_) async => SyncQueueEntry(
              atKey: 'k1.wavi@abandon', op: SyncQueueOp.delete, ts: 1, seq: 1));
      when(() => localSecondary.keyStore).thenReturn(_MockKeyStore());
      when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((_) async {
        await sync.stop();
        return 'data:[]';
      });

      await expectLater(
          sync.syncInternal(-1, SyncRequest()..result = SyncResult(),
              localCommitIdBeforeSync: 1),
          throwsA(isA<Exception>()));

      expect(recorded.at('INFO'), contains(contains('Stopping sync service')),
          reason: 'the recorder saw the stop, so a severe line would have '
              'been seen too');
      expect(recorded.at('SEVERE'), isEmpty,
          reason: 'the batch was abandoned because stop() was called; '
              '"sendBatch failed: Instance of _SyncAbandoned" was what a '
              'green run used to print for it');
    });

    test('a batch push the closed connection refuses is abandoned, not failed',
        () async {
      stubFreshClient();
      when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 1);
      when(() => localSecondary.peekSyncQueue(limit: any(named: 'limit')))
          .thenAnswer((_) async => ['k1.wavi@abandon']);
      when(() => localSecondary.readSyncQueueEntry(any())).thenAnswer(
          (_) async => SyncQueueEntry(
              atKey: 'k1.wavi@abandon', op: SyncQueueOp.delete, ts: 1, seq: 1));
      when(() => localSecondary.keyStore).thenReturn(_MockKeyStore());
      when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
          .thenThrow(StoppedException('the lookup for @abandon is closed'));

      await expectLater(
          sync.syncInternal(-1, SyncRequest()..result = SyncResult(),
              localCommitIdBeforeSync: 1),
          throwsA(isA<Exception>()));

      expect(recorded.at('SEVERE'), isEmpty,
          reason: 'the connection is closed because its owner stopped, which '
              'is not a failed push');
    });

    test(
        'a stop that lands while a batch response is being applied abandons '
        'the rest of the batch', () async {
      stubFreshClient();
      const first = 'k1.wavi@abandon';
      const second = 'k2.wavi@abandon';
      when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 2);
      when(() => localSecondary.peekSyncQueue(limit: any(named: 'limit')))
          .thenAnswer((_) async => [first, second]);
      when(() => localSecondary.readSyncQueueEntry(any())).thenAnswer(
          (invocation) async => SyncQueueEntry(
              atKey: invocation.positionalArguments.single as String,
              op: SyncQueueOp.delete,
              ts: 1,
              seq: 1));
      when(() => localSecondary.keyStore).thenReturn(_MockKeyStore());
      when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((_) async => 'data:${jsonEncode([
                    {
                      'id': 1,
                      'response': {'data': '7'}
                    },
                    {
                      'id': 2,
                      'response': {'data': '8'}
                    },
                  ])}');
      when(() => localSecondary.removeFromSyncQueueIfUnchanged(first, 1))
          .thenAnswer((_) async {
        await sync.stop();
        return true;
      });
      when(() => localSecondary.removeFromSyncQueueIfUnchanged(second, 1))
          .thenAnswer((_) async => true);

      await expectLater(
          sync.syncInternal(-1, SyncRequest()..result = SyncResult(),
              localCommitIdBeforeSync: 1),
          throwsA(isA<Exception>()));

      verify(() => localSecondary.removeFromSyncQueueIfUnchanged(first, 1))
          .called(1);
      verifyNever(
          () => localSecondary.removeFromSyncQueueIfUnchanged(second, 1));
      expect(recorded.at('SEVERE'), isEmpty,
          reason: 'the stop is not a failed batch entry; "exception processing '
              'batch response entry ...: Instance of \'_SyncAbandoned\'" was '
              'what a green run printed for it');
    });

    test(
        'a server entry the stop interrupts is abandoned, not logged as failed',
        () async {
      stubFreshClient();
      when(() => remote.executeVerb(any())).thenAnswer((_) async =>
          serverEntry('public:signing_publickey@abandon', operation: '+'));
      when(() => localSecondary.executeVerb(any(),
          cameFromServer: any(named: 'cameFromServer'))).thenAnswer((_) async {
        await sync.stop();
        throw AtKeyNotFoundException(
            'Failed to fetch the enrollment record for e1 from the atServer: '
            'The connection was closed by this client before a response '
            'arrived');
      });

      await expectLater(
          sync.syncInternal(5, SyncRequest()..result = SyncResult(),
              localCommitIdBeforeSync: 1),
          throwsA(isA<Exception>()));

      expect(recorded.at('SEVERE'), isEmpty,
          reason: 'an entry that failed because the stop closed the '
              'connection under it is not "Exception: ... while syncing '
              'entry to local"');
      expect(recorded.at('FINER'), contains(contains('Not syncing')),
          reason: 'the entry is dropped with a finer line naming the stop');
    });

    test(
        'a server entry failing because a connection it needed was closed for '
        'good abandons the round', () async {
      stubFreshClient();
      when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 0);
      when(() => remote.executeVerb(any())).thenAnswer((_) async =>
          serverEntry('public:signing_publickey@abandon', operation: '+'));
      when(() => localSecondary.executeVerb(any(),
              cameFromServer: any(named: 'cameFromServer')))
          .thenThrow(
              StoppedException('the lookup for @abandon has been closed'));

      await expectLater(
          sync.syncInternal(5, SyncRequest()..result = SyncResult(),
              localCommitIdBeforeSync: 1),
          throwsA(isA<Exception>()),
          reason: 'every later entry would fail the same way, and skipping '
              'them lets the cursor move past what was never applied');

      expect(sync.isStopped, isFalse,
          reason: 'the service itself was not stopped; the connection was');
      expect(recorded.at('SEVERE'), isEmpty);
    });

    test(
        'a delete the local store refuses is logged by its key, not as a '
        'type error', () async {
      stubFreshClient();
      when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 0);
      when(() => remote.executeVerb(any())).thenAnswer(
          (_) async => serverEntry('k1.__ssenv.wavi@abandon', operation: '-'));
      when(() => localSecondary.executeVerb(any(),
              cameFromServer: any(named: 'cameFromServer')))
          .thenThrow(UnAuthorizedException('not authorised for wavi'));

      final result = await sync.syncInternal(
          5, SyncRequest()..result = SyncResult(),
          localCommitIdBeforeSync: 1);

      expect(result.syncStatus, SyncStatus.success);
      expect(recorded.at('SEVERE'), isEmpty,
          reason: 'the refusal handler used to cast every builder to '
              'UpdateVerbBuilder, so a refused DELETE surfaced as a '
              'TypeError from inside the catch');
      expect(
          recorded.at('FINER'),
          contains(
              contains('Failed to sync k1.__ssenv.wavi@abandon caused by')),
          reason: 'the refusal is logged with the key it was about');
    });

    test('the round ends at its next step and touches nothing further',
        () async {
      final gate = Completer<List<String>>();
      when(() => localSecondary.peekSyncQueue()).thenAnswer((_) => gate.future);
      when(() => atClient.get(any())).thenAnswer((_) async => AtValue());

      final round = sync.syncInternal(5, SyncRequest()..result = SyncResult(),
          localCommitIdBeforeSync: 1);
      await Future<void>.delayed(Duration.zero);
      await sync.stop();
      gate.complete(<String>[]);

      await expectLater(round, throwsA(isA<Exception>()),
          reason: 'a stopped service abandons the round rather than '
              'finishing it against storage that may be closing');
      verifyNever(() => atClient.get(any()));
    });

    test('the same round completes when not stopped (control)', () async {
      when(() => localSecondary.peekSyncQueue())
          .thenAnswer((_) async => <String>[]);
      when(() => atClient.get(any())).thenAnswer((_) async => AtValue());

      try {
        await sync.syncInternal(5, SyncRequest()..result = SyncResult(),
            localCommitIdBeforeSync: 1);
      } catch (_) {}
      verify(() => atClient.get(any())).called(greaterThan(0));
    });
  });

  test(
      'syncQueueSyncSnapshot is null for a closed queue, as for an unopened one',
      () async {
    final atClient = _MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn('@snapshot');
    final box =
        await Hive.openBox<String>('snapshot_probe', bytes: Uint8List(0));
    final queue = AtSyncQueue(atSign: '@snapshot');
    await queue.open(store: HiveBoxSyncQueueStore(box));
    final ls = LocalSecondary(atClient, keyStore: null, syncQueue: queue);
    expect(ls.syncQueueSyncSnapshot, 0);
    await queue.close();
    expect(ls.syncQueueSyncSnapshot, isNull,
        reason: 'a closed queue has no size to report; null is what a caller '
            'already handles for a queue that never opened');
  });
}
