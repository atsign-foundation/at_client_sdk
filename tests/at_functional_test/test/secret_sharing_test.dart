// ignore_for_file: experimental_member_use

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Functional test for same-atSign pairwise secret sharing
/// ("alice to alice") against the virtualenv atServer.
///
/// Two clients of one atSign, each with its own local storage (modelling two
/// devices). Client B registers its key bundle and goes away; client A
/// registers, discovers B's bundle via a real `scan:showhidden:true`, shares
/// a secret (envelope syncs up as a normal self key); B comes back, syncs
/// the envelope down, verifies + decrypts + consumes it, and the deletion
/// syncs back to the server.
///
/// Both clients authenticate with the same demo PKAM keys (legacy auth, so
/// enrollmentId 'primary') — this exercises the several-clients-on-one-
/// enrollment case. The cross-enrollment case additionally relies on the
/// server's enrollment namespace authorization, which is enforced in
/// abstract_verb_handler.isAuthorized and covered by atServer tests.
class TestSharer
    with
        ApkamSigning,
        EnvelopeSigning,
        PairwiseClientRegistration,
        PairwiseSecretSharing {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('SecretSharingFT');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;

  TestSharer(this.atClient);
}

void main() {
  final atSign = '@alice🛠';
  final namespace = 'wavi';

  /// Re-initializes the AtClient singletons for [atSign] against a
  /// per-"device" storage path, so two clients of one atSign can run
  /// (sequentially) in one isolate.
  Future<AtClient> initClient(String device) async {
    AtClientManager.getInstance().reset();
    AtClientImpl.atClientInstanceMap.clear();
    final preference = TestUtils.getPreference(atSign)
      ..hiveStoragePath = 'test/hive/secret_sharing/$device'
      ..commitLogPath = 'test/hive/secret_sharing/$device/commit';
    final manager =
        await TestUtils.initAtClient(atSign, namespace, preference: preference);
    return manager.atClient;
  }

  /// Polls [probe] (nudging sync first) until it returns true or [timeout]
  /// elapses.
  Future<bool> syncAndPollUntil(
    AtClient atClient,
    Future<bool> Function() probe, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      atClient.syncService.sync();
      await Future.delayed(Duration(seconds: 2));
      if (await probe()) {
        return true;
      }
    }
    return false;
  }

  test('two clients of one atSign share a secret end to end', () async {
    final secretValue = 'ft-${DateTime.now().millisecondsSinceEpoch}';

    // ------- phase 1: client B registers its bundle, then goes away
    PersistedClientKeys? clientBKeys;
    var atClientB = await initClient('clientB');
    var sharerB = TestSharer(atClientB);
    sharerB.saveClientKeys = (keys) async => clientBKeys = keys;
    final bundleB = await sharerB.registerClient(namespaces: [namespace]);
    expect(clientBKeys, isNotNull);
    expect(bundleB.namespaces, [namespace]);

    // ------- phase 2: client A discovers B and shares a secret
    final atClientA = await initClient('clientA');
    final sharerA = TestSharer(atClientA);
    await sharerA.registerClient();

    // discovery runs a real authenticated scan with showhidden:true; B's
    // bundle is a hidden public key (public:__sskb-...) so this asserts the
    // server-side visibility design as well as signature verification
    final discovered = await sharerA.discoverClients();
    final discoveredB =
        discovered.where((b) => b.clientId == bundleB.clientId).toList();
    expect(discoveredB, hasLength(1),
        reason: 'A must discover B\'s bundle (and not its own)');
    expect(discovered.any((b) => b.clientId == sharerA.clientId), isFalse);

    // namespace-scoped discovery: B registered a bundle copy under the app
    // namespace (a real server-authorized self-key write); A finds exactly B
    // there, and finds nobody under a namespace no client registered for
    final inNamespace = await sharerA.discoverClients(namespace: namespace);
    expect(inNamespace.map((b) => b.clientId), [bundleB.clientId],
        reason: 'namespace-scoped discovery must return B');
    expect(await sharerA.discoverClients(namespace: 'nosuchns'), isEmpty);

    await sharerA.secretStore.putSecret(
        Secret(namespace: namespace, name: 'ft-secret', value: secretValue));
    expect(await sharerA.shareAllSecretsWith(discoveredB.single), 1);

    // the envelope is a normal self key: wait for A's sync to push it up
    final envelopeRegex = '.*\\.${bundleB.clientId}\\.__ssenv\\..*';
    expect(
        await syncAndPollUntil(atClientA, () async {
          final remote = await atClientA.getAtKeys(
              regex: envelopeRegex, useRemoteAtServer: true);
          return remote.length == 1;
        }),
        isTrue,
        reason: 'envelope must reach the atServer via sync');

    // ------- phase 3: client B comes back, syncs down, consumes
    atClientB = await initClient('clientB'); // same storage as phase 1
    sharerB = TestSharer(atClientB);
    sharerB.loadClientKeys = () async => clientBKeys;
    await sharerB.registerClient(); // same clientId, republishes bundle

    final received = <ReceivedSecret>[];
    final sub = sharerB.receivedSecrets.listen(received.add);

    expect(
        await syncAndPollUntil(atClientB, () async {
          await sharerB.sweepOnce();
          return received.length == 1;
        }),
        isTrue,
        reason: 'B must receive the secret after syncing the envelope down');

    expect(received.single.fromClientId, sharerA.clientId);
    expect(received.single.secret.name, 'ft-secret');
    expect(received.single.secret.value, secretValue);
    expect(received.single.secret.namespace, namespace);
    expect(sharerB.secretStore.getSecret(namespace, 'ft-secret')?.value,
        secretValue);

    // consumption deleted the envelope locally; the delete syncs back up
    expect(await atClientB.getAtKeys(regex: envelopeRegex), isEmpty);
    expect(
        await syncAndPollUntil(atClientB, () async {
          final remote = await atClientB.getAtKeys(
              regex: envelopeRegex, useRemoteAtServer: true);
          return remote.isEmpty;
        }),
        isTrue,
        reason: 'envelope deletion must sync back to the atServer');

    // ------- cleanup
    await sub.cancel();
    sharerB.stopListening();
    await sharerB.deregisterClient();
    await sharerA.deregisterClient();
  }, timeout: Timeout(Duration(minutes: 5)));

  tearDownAll(() async {
    AtClientManager.getInstance().reset();
    AtClientImpl.atClientInstanceMap.clear();
  });
}
