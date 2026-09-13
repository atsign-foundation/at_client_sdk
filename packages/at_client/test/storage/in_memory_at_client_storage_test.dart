import 'dart:io';

import 'package:at_client/sqlite.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

void main() {
  runStorageContract(
      'memory', (atSign) => InMemoryAtClientStorage(atSign: atSign));

  test('memory: nothing reaches disk, and nothing survives close', () async {
    final before = Directory.current.listSync().map((e) => e.path).toSet();
    final s = InMemoryAtClientStorage(atSign: '@memonly');
    await s.attach(FakeClient('@memonly', 'e1'));
    await s.syncQueue.enqueue('k@memonly', SyncQueueOp.updateAll);
    await s.close();
    expect(Directory.current.listSync().map((e) => e.path).toSet(), before,
        reason: 'an in-memory store that wrote a file would not be one');

    final again = InMemoryAtClientStorage(atSign: '@memonly');
    await again.attach(FakeClient('@memonly', 'e1'));
    expect(again.syncQueue.size, 0,
        reason: 'a fresh in-memory store starts empty');
    await again.close();
  });
}
