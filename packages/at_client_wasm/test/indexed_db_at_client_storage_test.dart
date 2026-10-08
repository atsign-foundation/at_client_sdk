// ignore_for_file: implementation_imports
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_client_wasm/src/storage/indexed_db_at_client_storage.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:test/test.dart';

import 'support/storage_contract.dart';

void main() {
  int counter = 0;
  String nextEnrollmentId() =>
      'e${counter++}_${DateTime.now().millisecondsSinceEpoch}';

  final dbToDelete = <(String, String)>[];

  tearDown(() async {
    for (final db in dbToDelete) {
      await IndexedDbAtClientStorage.deleteDatabase(
          atSign: db.$1, enrollmentId: db.$2);
    }
    dbToDelete.clear();
  });

  IndexedDbAtClientStorage makeStorage(String atSign, String enrollmentId) {
    dbToDelete.add((atSign, enrollmentId));
    return IndexedDbAtClientStorage(atSign: atSign, enrollmentId: enrollmentId);
  }

  runStorageContract('idb', (String atSign) {
    return makeStorage(atSign, nextEnrollmentId());
  });

  test('the same instance reopens after close and reads what it wrote',
      () async {
    final s = makeStorage('@alice', nextEnrollmentId());
    await s.openBackend();
    await s.keyStore.put('k1@alice', AtData()..data = 'v1');
    await s.closeBackend();

    await s.openBackend();
    expect((await s.keyStore.get('k1@alice'))?.data, 'v1');
    await s.closeBackend();
  });

  test('durability: records and queue survive restart', () async {
    final e = nextEnrollmentId();
    final s1 = makeStorage('@alice', e);
    await s1.openBackend();

    await s1.keyStore.put('k1@alice', AtData()..data = 'v1');
    await s1.keyStore.put('k2@alice', AtData()..data = 'v2');
    await s1.keyStore
        .put('local:lastreceivedservercommitid@alice', AtData()..data = '10');

    await s1.syncQueue.enqueue('k1@alice', SyncQueueOp.updateAll);
    await s1.syncQueue.enqueue('k2@alice', SyncQueueOp.updateAll);
    await s1.syncQueue.enqueue('k3@alice', SyncQueueOp.updateAll);

    await s1.closeBackend();

    final s2 = makeStorage('@alice', e);
    await s2.openBackend();

    expect((await s2.keyStore.get('k1@alice'))?.data, 'v1');
    expect((await s2.keyStore.get('k2@alice'))?.data, 'v2');
    expect(
        (await s2.keyStore.get('local:lastreceivedservercommitid@alice'))?.data,
        '10');

    expect(s2.syncQueue.size, 3);
    final entries = s2.syncQueue.persistedKeys.toList();
    expect(entries.length, 3);

    await s2.closeBackend();
  });

  test('isolation: different enrollmentIds give different DBs', () async {
    final e1 = nextEnrollmentId();
    final e2 = nextEnrollmentId();

    final s1 = makeStorage('@alice', e1);
    final s2 = makeStorage('@alice', e2);

    await s1.openBackend();
    await s2.openBackend();

    expect(s1.location, isNot(s2.location));

    await s1.keyStore.put('k@alice', AtData()..data = 'v1');

    expect(await s1.keyStore.exists('k@alice'), isTrue);
    expect(await s2.keyStore.exists('k@alice'), isFalse);

    await s1.closeBackend();
    await s2.closeBackend();
  });

  test('empty enrollmentId throws ArgumentError', () {
    expect(() => IndexedDbAtClientStorage(atSign: '@alice', enrollmentId: ''),
        throwsA(isA<ArgumentError>()));
  });
}
