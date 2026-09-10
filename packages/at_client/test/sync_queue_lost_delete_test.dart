// Pins that a local write racing an in-flight push cannot be lost.
//
// The shape: put(k) is being pushed by a sync round; delete(k) lands while the
// batch is in flight, replacing k's per-key queue entry. A success path that
// removes the entry BY KEY discards the delete with nothing left to retry it —
// the server keeps the update, the queue reads empty, and the client reports
// itself in sync, so an awaited delete() silently never syncs.
//
// Driven with a REAL LocalSecondary and sync queue (the race lives in the
// store), a mocked RemoteSecondary whose batch stub performs the racing delete
// so the interleaving is deterministic, and the real SyncServiceImpl push loop.

import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class _MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() => '@alice';

  @override
  AtClientPreference getPreferences() => AtClientPreference();
}

class _MockNotificationService extends Mock implements NotificationServiceImpl {
  @override
  Stream<at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<at_notification.AtNotification>().stream;
  }
}

void main() {
  final storageDir = '${Directory.current.path}/test/hive_lost_delete';
  const atSignStr = '@alice';

  late _MockAtClient atClient;
  late MockRemoteSecondary remote;
  late LocalSecondary local;
  late HiveAtPersistenceFactory factory;
  late SyncServiceImpl service;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
  });

  setUp(() async {
    AtClientImpl.atClientInstanceMap.remove(atSignStr);
    factory = HiveAtPersistenceFactory();
    final bundle = await factory.initialize(atSignStr,
        HivePersistenceConfig.clientDefaults(storagePath: storageDir));

    atClient = _MockAtClient();
    remote = MockRemoteSecondary();
    when(() => atClient.atSign).thenReturn(atSignStr.toAtsign());
    when(() => atClient.enrollmentId).thenReturn(null);
    when(() => atClient.persistenceBundle).thenReturn(bundle);
    when(() => atClient.notificationService)
        .thenReturn(_MockNotificationService());
    when(() => atClient.syncService).thenReturn(MockSyncService());

    local = LocalSecondary(atClient,
        keyStore: bundle.keyValueStore, onEvent: (_) {});
    local.enrollment = Enrollment()..namespace = {'*': 'rw'};
    when(() => atClient.getLocalSecondary()).thenReturn(local);
    // lastReceivedServerCommitId; also read by _getLocalCommitId.
    when(() => atClient.get(any()))
        .thenAnswer((_) async => AtValue()..value = '7');

    service = await SyncServiceImpl.create(atClient,
        atClientManager: MockAtClientManager(),
        remoteSecondary: remote,
        warmStartSync: false) as SyncServiceImpl;

    // The stats fetch _isInSync opens every round with.
    when(() => remote.executeVerb(any()))
        .thenAnswer((_) async => 'data:[{"value":"7"}]');
  });

  tearDown(() async {
    if (!service.isStopped) await service.stop();
    await factory.close();
    final dir = Directory(storageDir);
    if (await dir.exists()) dir.deleteSync(recursive: true);
  });

  AtKey testKey() => AtKey()
    ..key = 'racedkey'
    ..sharedBy = atSignStr
    ..namespace = 'wavi';

  test('a delete landing mid-push survives the push round and syncs next',
      () async {
    final key = testKey();
    await local.executeVerb(
        UpdateVerbBuilder()
          ..atKey = key
          ..value = 'v1',
        sync: true);
    final queued = await local.readSyncQueueEntry(key.toString());
    expect(queued!.op, SyncQueueOp.updateAll,
        reason: 'precondition: the update is what the round will push');

    final batchCommands = <String>[];
    var raced = false;
    when(() =>
            remote.executeCommand(any(that: startsWith('batch:')), auth: true))
        .thenAnswer((invocation) async {
      batchCommands.add(invocation.positionalArguments.first as String);
      if (!raced) {
        raced = true;
        // The race, made deterministic: the batch is "on the wire" and a
        // local delete replaces the queue entry before the response lands.
        await local.executeVerb(DeleteVerbBuilder()..atKey = testKey(),
            sync: true);
      }
      // The server accepts what the batch carried. data "7" so the cached
      // server commit id does not advance past the stubbed pull cursor.
      return 'data:[{"id":1,"response":{"data":"7"}}]';
    });

    service.sync();
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 300));

    expect(batchCommands, hasLength(1),
        reason: 'exactly one round has run; its batch carried the update');
    expect(batchCommands.single, contains('update'),
        reason: 'positive control: the first push was the update the race '
            'supersedes');

    final survivor = await local.readSyncQueueEntry(key.toString());
    expect(survivor, isNotNull,
        reason: 'the delete that landed mid-push was discarded by the '
            'push round\'s success path — the lost-delete defect');
    expect(survivor!.op, SyncQueueOp.delete);

    service.sync();
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 300));

    expect(batchCommands, hasLength(2),
        reason: 'the superseded entry must drive a second push round');
    expect(batchCommands[1], contains('delete:'),
        reason: 'the second batch must carry the delete to the server — '
            'a second update here would mean the queue kept the wrong op');
    expect(await local.readSyncQueueEntry(key.toString()), isNull,
        reason: 'the delete\'s own removal succeeds: its version matched');
  });
}
