// Unit tests for NoopSyncQueueStore — the SyncQueueStore that never
// persists anything, satisfying D-18 item 1 ("a queue which never
// enqueues and always reports empty satisfies the contract"). Backs
// RemoteOnlyAtClientStorage (PB-3 stage2c): once RemoteWriteThroughKeyStore
// (stage2b) delivers synchronously with its own retry, there is nothing
// left for a queue to redeliver.

import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/sync/sync_queue_store.dart';
import 'package:test/test.dart';

void main() {
  group('NoopSyncQueueStore', () {
    test('keys is empty, get returns null for any key', () {
      const store = NoopSyncQueueStore();
      expect(store.keys, isEmpty);
      expect(store.get('anything'), isNull);
    });

    test('put then get still returns null — nothing is persisted', () async {
      const store = NoopSyncQueueStore();
      await store.put('k1', 'record');
      expect(store.get('k1'), isNull);
      expect(store.keys, isEmpty);
    });

    test('clear and close complete without throwing', () async {
      const store = NoopSyncQueueStore();
      await store.clear();
      await store.close();
    });
  });

  group('AtSyncQueue.open with NoopSyncQueueStore', () {
    test('opens and enqueues without touching Hive', () async {
      final q = AtSyncQueue(atSign: '@noopqueue');
      await q.open(store: const NoopSyncQueueStore());

      expect(q.size, 0);
      expect(q.isEmpty, isTrue);

      await q.enqueue('@noopqueue:key', SyncQueueOp.update);

      // AtSyncQueue's in-memory FIFO is independent of the store — it
      // still tracks this enqueue for the current process's drain.
      // The store's no-op-ness is that nothing survives a reopen (below).
      expect(q.size, 1);
      expect(q.peek(), ['@noopqueue:key']);
    });

    test('a fresh open() never replays anything — nothing was persisted',
        () async {
      final first = AtSyncQueue(atSign: '@noopqueue2');
      await first.open(store: const NoopSyncQueueStore());
      await first.enqueue('@noopqueue2:key', SyncQueueOp.update);
      expect(first.size, 1);

      // Simulates a restart: a new AtSyncQueue instance, same (no-op) store.
      final second = AtSyncQueue(atSign: '@noopqueue2');
      await second.open(store: const NoopSyncQueueStore());

      expect(second.size, 0,
          reason: 'a Hive- or Sqlite-backed store would replay the entry '
              'here; the no-op store never persisted it in the first place');
      expect(second.isEmpty, isTrue);
      expect(second.peek(), isEmpty);
    });
  });
}
