import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:test/test.dart';

void main() {
  test(
      'a created client holds a HiveAtClientStorage, and its LocalSecondary '
      'shares that storage\'s queue rather than opening one of its own',
      () async {
    final dir = Directory.systemTemp.createTempSync('at_client_wiring_');
    final pref = AtClientPreference()
      ..hiveStoragePath = dir.path
      ..commitLogPath = '${dir.path}/commit';
    final client =
        await AtClientImpl.create('@storagewire', 'wavi', pref) as AtClientImpl;

    final storage = client.storage;
    expect(storage, isA<HiveAtClientStorage>());
    expect(client.persistenceBundle, isNotNull);

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
