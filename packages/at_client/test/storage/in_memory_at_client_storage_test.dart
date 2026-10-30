import 'dart:io';

import 'package:at_client/memory.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

/// Catalogue: features/at_client/web_safe.feature
void main() {
  group('The memory storage meets the storage contract', () {
    runStorageContract(
        'memory', (atSign) => InMemoryAtClientStorage(atSign: atSign),
        breakOpen: null);
  });

  test('Two memory storages share nothing', () async {
    final first = InMemoryAtClientStorage(atSign: '@memshare');
    final second = InMemoryAtClientStorage(atSign: '@memshare');
    addTearDown(first.close);
    addTearDown(second.close);
    await first.attach(FakeClient('@memshare', 'e1'));
    await second.attach(FakeClient('@memshare', 'e2'));

    await first.keyStore
        .put('public:phone.wavi@memshare', AtData()..data = '+44');
    await first.syncQueue
        .enqueue('public:phone.wavi@memshare', SyncQueueOp.updateAll);

    expect(await first.keyStore.exists('public:phone.wavi@memshare'), isTrue,
        reason: 'the premise: the write landed in the first storage');
    expect(await second.keyStore.exists('public:phone.wavi@memshare'), isFalse,
        reason: 'two clients of one atSign, each on its own memory storage, '
            'see each other\'s writes only once sync brings them');
    expect(second.syncQueue.size, 0);
  });

  test('Nothing outlives a memory storage', () async {
    final before = Directory.current.listSync().map((e) => e.path).toSet();
    final s = InMemoryAtClientStorage(atSign: '@memonly');
    await s.attach(FakeClient('@memonly', 'e1'));
    await s.keyStore.put('public:k.wavi@memonly', AtData()..data = 'v');
    await s.syncQueue.enqueue('k@memonly', SyncQueueOp.updateAll);
    await s.close();
    expect(Directory.current.listSync().map((e) => e.path).toSet(), before,
        reason: 'an in-memory store that wrote a file would not be one');

    final again = InMemoryAtClientStorage(atSign: '@memonly');
    await again.attach(FakeClient('@memonly', 'e1'));
    expect(again.syncQueue.size, 0,
        reason: 'a fresh in-memory store starts empty');
    expect(await again.keyStore.getKeys().then((s) => s.toList()), isEmpty);
    await again.close();
  });
}
