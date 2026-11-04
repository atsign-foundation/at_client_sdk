import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_io.dart'
    show FileAtKeysIo, secureSocketLookUps;
import 'package:at_client/memory.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// Catalogue: features/at_client/web_safe.feature
void main() {
  TestUtils.isolateStorage('memory_storage_live_test');

  test('A client on the memory storage works local-first', () async {
    final String atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final runId = const Uuid().v4();
    final storage = InMemoryAtClientStorage(atSign: atSign);
    final client = await Atsign(atSign).open(
        keys:
            FileAtKeysIo(filePath: (_) => 'test/testData/${atSign}_key.atKeys'),
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
        namespace: 'wavi',
        storage: storage,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: TestUtils.atDirectory);
    addTearDown(() async {
      await client.stop();
      await storage.close();
    });
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: client.syncService);

    final key =
        AtKey.public('memory-$runId', namespace: 'wavi', sharedBy: atSign)
            .build();
    expect(await client.put(key, 'local-first'), isTrue);

    expect(await storage.keyStore.exists(key.toString()), isTrue,
        reason: 'the write landed in the memory storage');
    expect((await client.get(key)).value, 'local-first',
        reason: 'the read is answered from the memory storage');

    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: client.syncService);
    final remote = await client.get(key,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    expect(remote.value, 'local-first',
        reason: 'the value reaches the atServer by sync');
  });
}
