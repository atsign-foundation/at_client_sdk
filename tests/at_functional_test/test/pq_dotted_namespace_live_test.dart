@Tags(['pq'])
library;

import 'package:at_client/at_client_io.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A collection in a dotted app namespace at pqActive: its records, the
/// copies it shares and its sub-collection items are sealed under the app
/// namespace's key, though every key it writes is read from its string form.
///
/// Catalogue: features/at_client/pq_dotted_namespace.feature
void main() {
  TestUtils.isolateStorage('pq_dotted_namespace_live_test');
  // NOTE: unique per run. A namespace key minted here takes a `_nskeylock`
  // whose ttl is a cooldown, so a fixed namespace fails on a second run.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'todos$runId.demos';
  const lifetime = Duration(days: 1);
  late String alice;
  late String bob;
  late AtClient aliceClient;
  late AtClient bobClient;

  Future<AtClient> open(String atSign) async {
    final loader = AtEncryptionKeysLoader.getInstance();
    final client = await Atsign(atSign).open(
        keys: InMemoryAtKeysIo.holding(
            atSign, loader.createAtKeysFromDemoKeys(atSign)),
        preference: TestUtils.getPreference(atSign, posture: PqPosture.pqActive)
          ..namespace = namespace,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: TestUtils.atDirectory,
        namespace: namespace,
        storage: TestUtils.storageFor(atSign));
    await loader.setEncryptionKeys(client, atSign);
    await (client as AtClientImpl).pqBootstrap!.startupComplete;
    return client;
  }

  Future<AtCollection<String>> todosOf(AtClient client) =>
      client.collection<String>('todos.$namespace', lifetime);

  /// The level [atSign]'s copy of [key] records its content key at.
  Future<Object?> ckNsOf(AtClient client, String key) async =>
      (await client.get(AtKey.fromString(key)))
          .metadata
          ?.appMetadata
          ?.additional?['ckNs'];

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    aliceClient = await open(alice);
    bobClient = await open(bob);
  });

  tearDownAll(() async {
    await aliceClient.stop();
    await bobClient.stop();
  });

  test(
      'A collection record in a dotted app namespace is written and read at '
      'pqActive', () async {
    final todos = await todosOf(aliceClient);

    await todos.create(obj: 'a todo', id: 't1');

    expect(await ckNsOf(aliceClient, 't1.todos.$namespace$alice'), namespace,
        reason: 'sealed under the app namespace, not its last label');
    expect((await todos.getOrNull('t1', alice.toAtsign()))?.obj, 'a todo');
  });

  test('A todo shared in a dotted namespace opens for the recipient', () async {
    final todos = await todosOf(aliceClient);
    await todos
        .create(obj: 'a shared todo', id: 't2', sharedWith: {bob.toAtsign()});
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: aliceClient.syncService, label: 'dotted-share');

    final shared = '$bob:t2.todos.$namespace$alice';
    expect((await bobClient.get(AtKey.fromString(shared))).value,
        contains('a shared todo'));
    expect(await ckNsOf(bobClient, shared), namespace,
        reason: "sealed under bob's key for the app namespace");
  });

  test('A sub-collection record is sealed under the app namespace', () async {
    final todos = await todosOf(aliceClient);
    final todo = await todos.create(obj: 'a todo with notes', id: 't3');
    final notes = todos.subCollection<String>(
        parent: todo, subName: 'notes', defaultExpiration: lifetime);

    await notes.create(obj: 'a note', id: 'n1');

    expect(await ckNsOf(aliceClient, 'n1.notes.t3.todos.$namespace$alice'),
        namespace);
    expect((await notes.getOrNull('n1', alice.toAtsign()))?.obj, 'a note');
  });
}
