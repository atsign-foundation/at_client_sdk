import 'package:at_client/at_client_io.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// upsert on a real client that holds a record under an over-long id whose
/// value it cannot decrypt, because it has no self encryption key: the item
/// is held, so the new-id rule does not refuse it, and the write that follows
/// cannot encrypt, so upsert refuses and the record keeps its value.
///
/// Catalogue: features/at_client/collection_item_ids.feature
void main() {
  TestUtils.isolateStorage('upsert_held_unopenable_live_test');
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'ups$runId.demos';
  final collection = 'todos.$namespace';
  final longId = 'a' * 65;
  const lifetime = Duration(days: 1);
  late String alice;
  late String key;

  Future<AtClient> open(AtKeys keys, String label) async {
    final client = await Atsign(alice).open(
        keys: InMemoryAtKeysIo.holding(alice, keys),
        preference: TestUtils.getPreference(alice, posture: PqPosture.legacy)
          ..namespace = namespace,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: TestUtils.atDirectory,
        namespace: namespace,
        storage: TestUtils.storageForPrincipal(alice, label));
    return client;
  }

  Future<AtClient> openWithEveryKey() async {
    final loader = AtEncryptionKeysLoader.getInstance();
    final client = await open(loader.createAtKeysFromDemoKeys(alice), 'every');
    await loader.setEncryptionKeys(client, alice);
    return client;
  }

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    key = '$longId.$collection$alice';
  });

  test(
      'Given a client without its self encryption key whose local storage holds a record under a 65-character id, when upsert is called with that id, then it refuses and the record keeps its value',
      () async {
    final writer = await openWithEveryKey();
    await writer.put(AtKey.fromString(key), 'old',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
    await writer.stop();

    final reader = await open(
        AtKeys.legacy(
          apkamPublicKey: pkamPublicKeyMap[alice]!,
          apkamPrivateKey: pkamPrivateKeyMap[alice]!,
          encryptionPublicKey: encryptionPublicKeyMap[alice]!,
          encryptionPrivateKey: encryptionPrivateKeyMap[alice]!,
        ),
        'noself');
    try {
      await FunctionalTestSyncService.getInstance()
          .syncData(syncSvc: reader.syncService, label: 'upsert-noself');
      final local = GetRequestOptions()..useRemoteAtServer = false;
      expect(
          await reader.getMeta(AtKey.fromString(key), getRequestOptions: local),
          isNotNull,
          reason: 'the control: local storage holds the record');
      await expectLater(
          reader.get(AtKey.fromString(key), getRequestOptions: local),
          throwsA(isA<AtException>()),
          reason: 'the control: this client cannot decrypt it');

      final todos = await reader.collection<String>(collection, lifetime);
      await expectLater(todos.upsert(obj: 'new', id: longId),
          throwsA(isA<CollectionOpException>()));
    } finally {
      await reader.stop();
    }

    final check = await openWithEveryKey();
    try {
      expect(
          (await check.get(AtKey.fromString(key),
                  getRequestOptions: GetRequestOptions()
                    ..useRemoteAtServer = true))
              .value,
          'old');
    } finally {
      await check.stop();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
