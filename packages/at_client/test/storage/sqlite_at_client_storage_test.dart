import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('at_client_sqlite_'));
  tearDown(() => dir.deleteSync(recursive: true));

  runStorageContract(
      'sqlite',
      (atSign) =>
          SqliteAtClientStorage.under(atSign: atSign, storagePath: dir.path));

  test('sqlite: the queue survives close and reopen, in order', () async {
    AtClientStorage make() => SqliteAtClientStorage.under(
        atSign: '@sqlitedur', storagePath: dir.path);
    final owner = FakeClient('@sqlitedur', 'e1');
    final first = make();
    await first.attach(owner);
    await first.syncQueue.enqueue('b@sqlitedur', SyncQueueOp.updateAll, ts: 2);
    await first.syncQueue.enqueue('a@sqlitedur', SyncQueueOp.delete, ts: 1);
    await first.close();

    final second = make();
    await second.attach(owner);
    expect(second.syncQueue.peek(), ['a@sqlitedur', 'b@sqlitedur'],
        reason: 'pending pushes are durable and replay in timestamp order, '
            'which is what makes this a real backend rather than a cache');
    await second.close();
  });
}
