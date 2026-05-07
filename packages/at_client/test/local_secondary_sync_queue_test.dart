// Phase 4 tests for the `decouple-sync-from-commit-log` refactor:
// LocalSecondary.executeVerb's new contract for enqueuing
// client→server writes into the sync queue, and skipping enqueue
// when the write is a server replay (`cameFromServer: true`).
//
// Distinct from `local_secondary_test.dart` (verb-builder shape /
// keystore CRUD) and `at_sync_queue_test.dart` (queue mechanics in
// isolation). This file tests the wiring between them.

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

void main() {
  const storageDir = 'test/hive';
  const atSign = '@alice';

  Future<LocalSecondary> setUpLocalSecondary() async {
    AtClientImpl.atClientInstanceMap.remove(atSign);
    var commitLogInstance = await AtCommitLogManagerImpl.getInstance()
        .getCommitLog(atSign, commitLogPath: storageDir);
    var persistenceManager = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(atSign)!;
    await persistenceManager.getHivePersistenceManager()!.init(storageDir);
    persistenceManager.getSecondaryKeyStore()!.commitLog = commitLogInstance;

    final atClientManager = AtClientManager(atSign);
    final preference = AtClientPreference()
      ..syncRegex = ''
      ..hiveStoragePath = storageDir
      ..commitLogPath = '$storageDir/commit';
    final atClient = await AtClientImpl.create(
      atSign,
      'wavi',
      preference,
      atClientManager: atClientManager,
    );
    return LocalSecondary(atClient);
  }

  Future<void> tearDownLocalSecondary() async {
    try {
      await SecondaryPersistenceStoreFactory.getInstance().close();
      await AtCommitLogManagerImpl.getInstance().close();
      // Close every Hive box (including the sync-queue box, which the
      // factory closures above don't know about) so the next setUp
      // doesn't reattach to leftover in-memory state.
      await Hive.close();
      AtClientImpl.atClientInstanceMap.remove(atSign);
      final dir = Directory(storageDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      print('teardown error: $e');
    }
  }

  group('LocalSecondary sync-queue enqueue (phase 4)', () {
    setUp(() async {});
    tearDown(() async => await tearDownLocalSecondary());

    test('public key write enqueues with op=updateAll', () async {
      final localSecondary = await setUpLocalSecondary();
      final builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'alice@example.com';

      await localSecondary.executeVerb(builder, sync: true);

      // Both the in-memory queue AND the persisted record must be
      // populated. atKey is the canonical string form.
      final atKey = builder.buildKey();
      expect(atKey, contains('public:email'));
      final pending = await localSecondary.peekSyncQueue();
      expect(pending, [atKey]);
      final entry = await localSecondary.readSyncQueueEntry(atKey);
      expect(entry, isNotNull);
      expect(entry!.op, SyncQueueOp.updateAll);
    });

    test('shared key write enqueues with op=updateAll', () async {
      final localSecondary = await setUpLocalSecondary();
      final builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'phone'
          ..sharedBy = atSign
          ..sharedWith = '@bob'
          ..metadata = Metadata())
        ..value = 'cipher';

      await localSecondary.executeVerb(builder, sync: true);

      final atKey = builder.buildKey();
      final pending = await localSecondary.peekSyncQueue();
      expect(pending, contains(atKey));
      final entry = await localSecondary.readSyncQueueEntry(atKey);
      expect(entry!.op, SyncQueueOp.updateAll);
    });

    test('updateMeta write enqueues with op=updateMeta', () async {
      final localSecondary = await setUpLocalSecondary();
      // First create the key so updateMeta has something to update.
      await localSecondary.executeVerb(
        UpdateVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'phone'
            ..sharedBy = atSign
            ..metadata = (Metadata()..isPublic = true))
          ..value = '12345',
        sync: true,
      );

      final metaBuilder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'phone'
          ..sharedBy = atSign
          ..metadata = (Metadata()
            ..isPublic = true
            ..ttl = 60000))
        ..operation = AtConstants.updateMeta;

      await localSecondary.executeVerb(metaBuilder, sync: true);

      final atKey = metaBuilder.buildKey();
      final entry = await localSecondary.readSyncQueueEntry(atKey);
      // The latest write wins on the persisted record. The
      // updateMeta call follows the original update; ts on the
      // record is the most recent enqueue and op is updateMeta.
      expect(entry, isNotNull);
      expect(entry!.op, SyncQueueOp.updateMeta);
    });

    test('delete enqueues with op=delete', () async {
      final localSecondary = await setUpLocalSecondary();
      // Create then delete to exercise the typical lifecycle.
      await localSecondary.executeVerb(
        UpdateVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'temp'
            ..sharedBy = atSign
            ..metadata = (Metadata()..isPublic = true))
          ..value = 'will be deleted',
        sync: true,
      );

      final deleteBuilder = DeleteVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'temp'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true));
      await localSecondary.executeVerb(deleteBuilder, sync: true);

      final atKey = deleteBuilder.buildKey();
      final entry = await localSecondary.readSyncQueueEntry(atKey);
      // UPDATE → DELETE collapses to DELETE on the persisted record.
      expect(entry!.op, SyncQueueOp.delete);
    });

    test('local: key write does NOT enqueue', () async {
      final localSecondary = await setUpLocalSecondary();
      final builder = UpdateVerbBuilder()
        ..atKey = AtKey.local('marker', atSign).build()
        ..value = 'true';

      await localSecondary.executeVerb(builder, sync: true);

      // Local keys are excluded by the syncEligibility predicate.
      expect(await localSecondary.syncQueueSize, 0);
    });

    test('cameFromServer=true skips enqueue for normally-eligible key',
        () async {
      final localSecondary = await setUpLocalSecondary();
      final builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'alice@example.com';

      await localSecondary.executeVerb(
        builder,
        sync: true,
        cameFromServer: true,
      );

      // Server-replay writes never enqueue — no queue entry, no
      // server-bound bounce.
      expect(await localSecondary.syncQueueSize, 0);
    });

    test(
        'second write to same key keeps in-memory FIFO position '
        'but updates persisted ts/op', () async {
      final localSecondary = await setUpLocalSecondary();

      await localSecondary.executeVerb(
        UpdateVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'phone'
            ..sharedBy = atSign
            ..metadata = (Metadata()..isPublic = true))
          ..value = 'first',
        sync: true,
      );
      await localSecondary.executeVerb(
        UpdateVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'email'
            ..sharedBy = atSign
            ..metadata = (Metadata()..isPublic = true))
          ..value = 'first',
        sync: true,
      );
      // Re-write phone — should NOT move it to the end of the
      // in-memory queue.
      await localSecondary.executeVerb(
        UpdateVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'phone'
            ..sharedBy = atSign
            ..metadata = (Metadata()..isPublic = true))
          ..value = 'second',
        sync: true,
      );

      final pending = await localSecondary.peekSyncQueue();
      expect(pending.length, 2);
      expect(pending.first, contains('public:phone'));
      expect(pending.last, contains('public:email'));
    });

    test('shouldEnqueueForSync predicate', () {
      // Unit-test the predicate directly so the rules are pinned
      // independently of the runtime path.
      expect(
        LocalSecondary.shouldEnqueueForSync('public:email.wavi@alice'),
        isTrue,
        reason: 'public keys are sync-eligible',
      );
      expect(
        LocalSecondary.shouldEnqueueForSync('phone.wavi@alice'),
        isTrue,
        reason: 'self keys are sync-eligible',
      );
      expect(
        LocalSecondary.shouldEnqueueForSync('@bob:phone.wavi@alice'),
        isTrue,
        reason: 'shared keys are sync-eligible',
      );
      expect(
        LocalSecondary.shouldEnqueueForSync('local:marker@alice'),
        isFalse,
        reason: 'local keys are NOT sync-eligible',
      );
      expect(
        LocalSecondary.shouldEnqueueForSync('cached:@bob:phone.wavi@alice'),
        isFalse,
        reason: 'cached shared keys are NOT sync-eligible '
            '(they came FROM the server)',
      );
      expect(
        LocalSecondary.shouldEnqueueForSync('cached:public:email.wavi@bob'),
        isFalse,
        reason: 'cached public keys are NOT sync-eligible',
      );
    });
  });
}
