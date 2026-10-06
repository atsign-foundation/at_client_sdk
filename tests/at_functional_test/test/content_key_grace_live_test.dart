// The PQ bootstrap and its key ring are @experimental; this drives them.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A superseded content key is kept for its grace, so a recipient that was
/// offline when a notification was sent under it can still open it after the
/// sender has rotated.
void main() {
  TestUtils.isolateStorage('content_key_grace_live_test');
  // NOTE: unique per run. A namespace key minted here takes a `_nskeylock`
  // whose ttl is a cooldown, so a fixed namespace fails on a second run.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final nsKeep = 'ckkeep$runId';
  final nsRotate = 'ckrot$runId';
  late String alice;
  late String bob;
  final keysOf = <String, InMemoryAtKeysIo>{};

  // NOTE: one keys object per atSign for the whole run, so a reopened client
  // presents as the enrollment its first session ended as.
  Future<AtClient> open(String atSign) async {
    final loader = AtEncryptionKeysLoader.getInstance();
    final client = await Atsign(atSign).open(
        keys: keysOf[atSign] ??= InMemoryAtKeysIo.holding(
            atSign, loader.createAtKeysFromDemoKeys(atSign)),
        preference: TestUtils.getPreference(atSign,
            posture: PqPosture.pqActive)
          ..namespace = nsKeep,
        namespace: nsKeep,
        storage: TestUtils.storageFor(atSign));
    await loader.setEncryptionKeys(client, atSign);
    await (client as AtClientImpl).pqBootstrap!.startupComplete;
    return client;
  }

  CkManager managerOf(AtClient client) =>
      (CryptoConfig.forClient(client).lookup(symmetricAesGcmCryptoProviderId)
              as SymmetricAesGcmProvider)
          .ckManager!;

  AtKey valueKey(String ns) => AtKey.fromString('$bob:msg.$ns$alice')
    ..metadata.namespaceAware = false;

  test(
      'a notification sent under a key that is then replaced still opens for '
      'a recipient that never fetched the key', () async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final aliceClient = await open(alice);
    var bobClient = await open(bob);
    addTearDown(aliceClient.stop);
    for (final ns in [nsKeep, nsRotate]) {
      expect((await bobClient.ensureReachable(ns)).isReachable, isTrue,
          reason: '$bob must publish a namespace key for $ns');
    }
    // NOTE: offline from before the sends until after the rotation. A running
    // recipient syncs its cached copy of the conveyance and holds the key
    // before anything could collect it.
    await bobClient.stop();

    for (final ns in [nsKeep, nsRotate]) {
      await aliceClient.notificationService.notify(
          NotificationParams.forUpdate(valueKey(ns), value: 'sent in $ns'),
          checkForFinalDeliveryStatus: false);
    }
    final cache = CryptoConfig.forClient(aliceClient).contentKeyCache!;
    final superseded = cache.current(bob, nsRotate)!.ckKid;
    final context = CryptoContext(atClient: aliceClient);
    Future<void> sync(String label) => FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: aliceClient.syncService, label: label);

    /// One collection pass that answered, syncing and asking again while the
    /// collector refuses because sync has not caught up: a round pushes after
    /// it pulls, so right after one the atServer can be ahead of the pull
    /// watermark until the next, and the SDK's own passes wait for that too.
    Future<int> collectOnce(String label) async {
      for (var attempt = 0; attempt < 20; attempt++) {
        final answer = await managerOf(aliceClient).tryCollect(context);
        if (answer != null) return answer;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await sync('$label-$attempt');
      }
      fail('no collection pass answered in 20 attempts: sync never caught up');
    }

    await managerOf(aliceClient).rotateContentKey(context, valueKey(nsRotate));
    await managerOf(aliceClient).idle;
    // NOTE: a collection deletes locally and sync pushes it, so a pass is run
    // over a caught-up store and pushed before the atServer is asked.
    await sync('ck-grace-rotated');
    // NOTE: a pass that answered, so "kept" below is its decision and not a
    // pass that never looked; the zero-grace control collects this same key.
    await collectOnce('ck-grace-retry');
    await sync('ck-grace-collected');

    final conveyance = '$bob:$superseded.__ck.$nsRotate$alice';
    Future<bool> served() async {
      try {
        await aliceClient
            .getRemoteSecondary()!
            .executeCommand('llookup:$conveyance\n', auth: true);
        return true;
      } on KeyNotFoundException {
        // NOTE: only a key the atServer does not hold reads as collected; an
        // outage or a refusal is this test's failure, not a collection.
        return false;
      }
    }

    expect(await served(), isTrue,
        reason: 'superseded just now, so kept although nothing cites it');

    bobClient = await open(bob);
    addTearDown(bobClient.stop);
    // NOTE: listed and opened through the subscriber's own transformer: the
    // reopened client's monitor replays its backlog during open(), before any
    // subscriber exists.
    final listed = (await bobClient
        .getRemoteSecondary()!
        .executeCommand('notify:list:msg.ck(keep|rot)$runId\n', auth: true))!;
    final notifications = AtNotification.fromJsonList([
      for (final e in jsonDecode(listed.substring('data:'.length)) as List)
        (e as Map).cast<String, dynamic>()
    ]);
    for (final ns in [nsKeep, nsRotate]) {
      final sent = notifications.singleWhere((n) => n.key.contains(ns));
      final opened = await NotificationResponseTransformer(bobClient)
          .transform(Tuple<AtNotification, NotificationConfig>()
            ..one = sent
            ..two = (NotificationConfig()..shouldDecrypt = true))
          .timeout(const Duration(seconds: 60));
      expect(opened.value, 'sent in $ns',
          reason: ns == nsKeep
              ? 'the control: a key nobody replaced'
              : 'its key was replaced, and is kept for its grace');
    }

    // NOTE: the control for "kept": the same key, now, with no grace. Its
    // going proves a pass could run, so only the grace kept it above.
    aliceClient.getPreferences()!.crypto = CryptoConfig.nskey(
        keyRing: (aliceClient as AtClientImpl).pqBootstrap!.ring,
        supersededCkGrace: Duration.zero);
    var collected = false;
    for (var attempt = 0; attempt < 20 && !collected; attempt++) {
      await collectOnce('ck-grace-none-$attempt');
      await sync('ck-grace-none-$attempt');
      collected = !await served();
      if (!collected) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    expect(collected, isTrue,
        reason: 'with no grace, the same key nothing cites is collected');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
