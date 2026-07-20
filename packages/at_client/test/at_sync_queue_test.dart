// Unit tests for AtSyncQueue — the persisted+in-memory queue that
// SyncServiceImpl drains for client→server writes. These tests
// cover the queue mechanics in isolation; the wiring against
// LocalSecondary lives in `local_secondary_sync_queue_test.dart`.
//
// Each test gets its own temp Hive directory so there's no leakage
// across runs.

import 'dart:io';

import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('at_sync_queue_test_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    // Close every open Hive box; Hive doesn't expose a "close all"
    // outside `Hive.close()` itself, which is what we want.
    await Hive.close();
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  group('AtSyncQueue.open', () {
    test('idempotent — second call is a no-op', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();
      await q.open(); // must not throw, must not reopen the box
      expect(q.size, 0);
      await q.close();
    });

    test('replays persisted entries into in-memory queue, ordered by ts',
        () async {
      // Round 1: write three entries with explicit ts values out of
      // insertion order, then close.
      final q1 = AtSyncQueue(atSign: '@alice');
      await q1.open();
      await q1.enqueue('phone.demo@alice', SyncQueueOp.update, ts: 200);
      await q1.enqueue('email.demo@alice', SyncQueueOp.delete, ts: 100);
      await q1.enqueue('city.demo@alice', SyncQueueOp.updateAll, ts: 300);
      await q1.close();

      // Round 2: reopen — replay should ts-sort.
      final q2 = AtSyncQueue(atSign: '@alice');
      await q2.open();
      expect(q2.peek(), [
        'email.demo@alice', // ts 100 first
        'phone.demo@alice', // ts 200
        'city.demo@alice', // ts 300 last
      ]);
      await q2.close();
    });

    test('skips malformed persisted entries with a warning', () async {
      // Pre-populate the raw box with one good and one malformed entry.
      final boxName = AtSyncQueue.boxNameForAtSign('@alice');
      final box = await Hive.openBox<String>(boxName);
      await box.put('ok.demo@alice', '{"op":"update","ts":42}');
      await box.put('broken.demo@alice', 'not json');
      await box.close();

      final q = AtSyncQueue(atSign: '@alice');
      await q.open();
      // Only the well-formed entry survives.
      expect(q.peek(), ['ok.demo@alice']);
      await q.close();
    });
  });

  group('AtSyncQueue.enqueue', () {
    test('persists op + ts and adds atKey to the in-memory FIFO', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();

      final tsBefore = DateTime.now().millisecondsSinceEpoch;
      await q.enqueue('phone.demo@alice', SyncQueueOp.update);
      final tsAfter = DateTime.now().millisecondsSinceEpoch;

      expect(q.size, 1);
      expect(q.peek(), ['phone.demo@alice']);
      final entry = q.readEntry('phone.demo@alice');
      expect(entry, isNotNull);
      expect(entry!.atKey, 'phone.demo@alice');
      expect(entry.op, SyncQueueOp.update);
      expect(entry.ts, inInclusiveRange(tsBefore, tsAfter));
      await q.close();
    });

    test(
        'second enqueue for same key overwrites op+ts but preserves '
        'in-memory FIFO position', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();

      await q.enqueue('phone.demo@alice', SyncQueueOp.update, ts: 100);
      await q.enqueue('email.demo@alice', SyncQueueOp.update, ts: 200);
      // Re-enqueue phone with later ts — should NOT move to the end of
      // the in-memory queue; FIFO position from first insertion is
      // retained (LinkedHashSet semantics).
      await q.enqueue('phone.demo@alice', SyncQueueOp.delete, ts: 300);

      expect(q.size, 2);
      expect(q.peek(), ['phone.demo@alice', 'email.demo@alice']);
      final entry = q.readEntry('phone.demo@alice');
      expect(entry!.op, SyncQueueOp.delete,
          reason: 'most recent op wins on the persisted record');
      expect(entry.ts, 300);
      await q.close();
    });

    test('UPDATE then DELETE for same key collapses to DELETE on persist',
        () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();

      await q.enqueue('phone.demo@alice', SyncQueueOp.updateAll, ts: 100);
      await q.enqueue('phone.demo@alice', SyncQueueOp.delete, ts: 200);

      expect(q.size, 1, reason: 'in-memory dedup by atKey');
      expect(q.readEntry('phone.demo@alice')!.op, SyncQueueOp.delete);
      await q.close();
    });
  });

  group('AtSyncQueue.peek + size', () {
    test('peek limit caps the result', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();
      for (var i = 0; i < 10; i++) {
        await q.enqueue('k$i.demo@alice', SyncQueueOp.update, ts: i);
      }

      expect(q.size, 10);
      expect(q.peek(limit: 3),
          ['k0.demo@alice', 'k1.demo@alice', 'k2.demo@alice']);
      expect(q.peek(limit: 100).length, 10);
      expect(q.peek().length, 10);
      await q.close();
    });

    test('isEmpty / isNotEmpty track size', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();
      expect(q.isEmpty, isTrue);
      expect(q.isNotEmpty, isFalse);

      await q.enqueue('phone.demo@alice', SyncQueueOp.update);
      expect(q.isEmpty, isFalse);
      expect(q.isNotEmpty, isTrue);
      await q.close();
    });
  });

  group('AtSyncQueue.remove', () {
    test('removes from both in-memory and persisted', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();

      await q.enqueue('phone.demo@alice', SyncQueueOp.update, ts: 100);
      await q.enqueue('email.demo@alice', SyncQueueOp.update, ts: 200);
      expect(q.size, 2);

      await q.remove('phone.demo@alice');

      expect(q.size, 1);
      expect(q.peek(), ['email.demo@alice']);
      expect(q.readEntry('phone.demo@alice'), isNull);
      // Survives reopen.
      await q.close();
      final q2 = AtSyncQueue(atSign: '@alice');
      await q2.open();
      expect(q2.peek(), ['email.demo@alice']);
      await q2.close();
    });

    test('remove of non-existent key is a no-op', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();
      await q.remove('never.existed@alice'); // must not throw
      expect(q.size, 0);
      await q.close();
    });
  });

  group('AtSyncQueue.boxNameForAtSign', () {
    test('is deterministic and prefixed', () {
      final n1 = AtSyncQueue.boxNameForAtSign('@alice');
      final n2 = AtSyncQueue.boxNameForAtSign('@alice');
      expect(n1, n2);
      expect(n1.startsWith('syncqueue_'), isTrue);
    });

    test('different atSigns get different box names', () {
      final n1 = AtSyncQueue.boxNameForAtSign('@alice');
      final n2 = AtSyncQueue.boxNameForAtSign('@bob');
      expect(n1, isNot(n2));
    });
  });

  group('AtSyncQueue lifecycle', () {
    test('use before open throws StateError', () async {
      final q = AtSyncQueue(atSign: '@alice');
      expect(() => q.size, throwsStateError);
      expect(() => q.peek(), throwsStateError);
      expect(() => q.readEntry('foo'), throwsStateError);
      expect(q.enqueue('foo@alice', SyncQueueOp.update), throwsStateError);
      expect(q.remove('foo@alice'), throwsStateError);
    });

    test('use after close throws StateError', () async {
      final q = AtSyncQueue(atSign: '@alice');
      await q.open();
      await q.enqueue('phone.demo@alice', SyncQueueOp.update);
      await q.close();
      expect(() => q.size, throwsStateError);
    });
  });
}
