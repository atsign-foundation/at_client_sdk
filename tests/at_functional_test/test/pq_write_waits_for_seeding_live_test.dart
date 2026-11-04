@Tags(['pq'])
library;

import 'package:at_client/at_client_io.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A write and a share a pqActive client makes the moment it opens, before its
/// start-up has published its namespace key, complete once it has.
///
/// Catalogue: features/at_client/pq_write_waits_for_seeding.feature
void main() {
  TestUtils.isolateStorage('pq_write_waits_for_seeding_live_test');
  // NOTE: unique per run. A namespace key minted here takes a `_nskeylock`
  // whose ttl is a cooldown, so a fixed namespace fails on a second run.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'early$runId.demos';

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
    return client;
  }

  Future<Object?> ckNsOf(AtClient client, AtKey key) async =>
      (await client.get(key)).metadata?.appMetadata?.additional?['ckNs'];

  test(
      'A write right after opening completes once start-up has seeded, and a '
      'share at once', () async {
    final String alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final String bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final bobClient = await open(bob);
    addTearDown(bobClient.stop);
    await (bobClient as AtClientImpl).pqBootstrap!.startupComplete;
    expect((await bobClient.ensureReachable(namespace)).outcome,
        AtReachability.alreadyReachable,
        reason: 'the premise: bob seeded his key beforehand');

    final aliceClient = await open(alice);
    addTearDown(aliceClient.stop);
    expect((aliceClient as AtClientImpl).pqBootstrap!.startUpSeeding.isFinished,
        isFalse,
        reason: "the premise: alice's start-up has not yet seeded");
    final own = AtKey.fromString('x.$namespace$alice');
    final shared = AtKey.fromString('$bob:y.$namespace$alice');

    await aliceClient.put(own, 'for alice');
    await aliceClient.put(shared, 'for bob');

    expect(await ckNsOf(aliceClient, own), namespace,
        reason: "sealed under alice's own key");
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: aliceClient.syncService, label: 'early-share');
    final read = await bobClient.get(AtKey.fromString(shared.toString()));
    expect(read.value, 'for bob');
    expect(read.metadata?.appMetadata?.additional?['ckNs'], namespace,
        reason: "sealed under bob's key");
  });
}
