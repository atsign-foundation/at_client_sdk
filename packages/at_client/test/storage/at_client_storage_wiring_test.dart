import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {}

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

  test('a bundle and an injected keystore together are refused, not merged',
      () async {
    // NOTE: an injected keystore skips the storage block entirely — keystore
    // AND sync queue — so accepting both would silently pair the named
    // keystore with a queue on the global Hive instance.
    final dir = Directory.systemTemp.createTempSync('at_client_both_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage =
        HiveAtClientStorage(atSign: '@bothstores', storagePath: dir.path);
    addTearDown(storage.close);

    await expectLater(
        AtClientImpl.create('@bothstores', 'wavi',
            AtClientPreference()..hiveStoragePath = dir.path,
            storage: storage, localSecondaryKeyStore: _MockKeyStore()),
        throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message',
            contains('replaces it rather than combining'))),
        reason: 'the two name different stores, so one of them would be '
            'silently dropped — and it is the bundle, taking the isolated '
            'sync queue with it');

    expect(AtClientImpl.atClientInstanceMap.containsKey('@bothstores'), isFalse,
        reason: 'refused before anything was filed, so a second attempt is not '
            'handed a half-built client');
  });
}
