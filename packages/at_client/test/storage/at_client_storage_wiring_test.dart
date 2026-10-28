import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:test/test.dart';

void main() {
  test(
      'a created client holds the storage it was given, and its LocalSecondary '
      'shares that storage\'s queue rather than opening one of its own',
      () async {
    final dir = Directory.systemTemp.createTempSync('at_client_wiring_');
    final given = HiveAtClientStorage(
        atSign: '@storagewire', storagePath: dir.path, closedByClient: true);
    final client = await AtClientImpl.create(
            '@storagewire', 'wavi', AtClientPreference(), storage: given)
        as AtClientImpl;

    final storage = client.storage;
    expect(storage, same(given));

    await storage!.syncQueue
        .enqueue('k.wavi@storagewire', SyncQueueOp.updateAll);
    expect(client.localSecondary!.syncQueueSyncSnapshot, 1,
        reason: 'the queue LocalSecondary reads must be the one the storage '
            'owns, or a write and its push live in different queues');

    await storage.close();
    AtClientImpl.atClientInstanceMap.remove('@storagewire');
    dir.deleteSync(recursive: true);
  });
}
