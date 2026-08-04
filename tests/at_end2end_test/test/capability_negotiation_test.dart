// The rollout surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// Scheme negotiation across two real atSigns — the B4 cluster.
///
/// One atSign cannot prove this. What a sender writes is decided by what the
/// *recipient's* fleet advertises, fetched cross-atSign by exact lookup and
/// verified against the publishing enrollment's `_apsk`; and the recipient's
/// readiness must not decide what the sender writes for **herself**. Both
/// properties collapse into tautologies when the two atSigns are the same one.
void main() {
  late String alice;
  late String bob;
  final namespace = TestConstants.namespace;

  // Markers are mutable and long-lived, so a namespace shared with other tests
  // — or with an earlier run of this one — would let a leftover readiness
  // declaration satisfy the not-ready arm below.
  final pqNamespace = 'b4cap${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final authType = ConfigUtil.getYaml()['authType'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(alice, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(bob, namespace, authType);
  });

  /// A client on the **era default** — reads the post-quantum path, writes
  /// legacy until a marker says otherwise. That is the shape every rebuilt
  /// client in the fleet actually has, and the only one whose writes the
  /// markers can move.
  Future<({AtClient client, PublishedNskeyKeyRing ring})> eraDefaultClient(
      String atSign) async {
    final manager = await AtClientManager.getInstance().setCurrentAtSign(
        atSign, namespace, TestPreferences.getInstance().getPreference(atSign));
    final client = manager.atClient;
    // The ring the config is built with is the one the read path resolves
    // privates through, so minting has to go through this same instance. A
    // second ring would publish a key whose private the client cannot reach,
    // and the record would be written and then unopenable — which is what the
    // first run of this test did.
    final ring = PublishedNskeyKeyRing(client);
    client.getPreferences()!.crypto =
        CryptoConfig.readsNskeyWritesLegacy(keyRing: ring);

    // The capability cache's ttl is the lever on how long a flip goes
    // unnoticed; the default is fifteen minutes, and a test that waited one
    // out would take fifteen minutes. Zero here so a flip published by the
    // other atSign is seen on the next write.
    PublishedCapabilities.setForClient(
        client, PublishedCapabilities(client, ttl: Duration.zero));
    return (client: client, ring: ring);
  }

  AtKey toBob(String name) => AtKey()
    ..key = name
    ..namespace = pqNamespace
    ..sharedWith = bob
    ..sharedBy = alice;

  String unique(String prefix) =>
      '$prefix.${DateTime.now().microsecondsSinceEpoch}';

  test(
      'UC-B4.1/B4.3/B4.4 · what alice writes to bob follows bob\'s marker, and '
      'her own self records follow hers', () async {
    // --- bob comes up not-ready, with a namespace key published ------------
    // The key matters: without it the post-quantum arm would fail cold start
    // rather than be gated, and the not-ready arm would pass for the wrong
    // reason.
    final bobSide = await eraDefaultClient(bob);
    final bobClient = bobSide.client;
    await bobSide.ring.mintAndPublish(pqNamespace);
    final bobRollout = CryptoRollout(bobClient);
    await bobRollout.publishNotReady(pqNamespace);
    await E2ESyncService.getInstance().syncData(bobClient.syncService);

    // --- alice comes up, also not-ready for her own scope ------------------
    final aliceSide = await eraDefaultClient(alice);
    final aliceClient = aliceSide.client;
    await aliceSide.ring.mintAndPublish(pqNamespace);
    await CryptoRollout(aliceClient).publishNotReady(pqNamespace);

    // What alice can actually see of bob, asserted rather than inferred from
    // what she writes: a marker she cannot read is indistinguishable from one
    // that says legacy-only, and would make the arm below pass for the wrong
    // reason.
    expect(await CryptoRollout(aliceClient).advertisedBy(bob, pqNamespace),
        {legacyCryptoProviderId},
        reason: 'alice must be able to fetch and verify bob\'s marker across '
            'atSigns — that read is the whole input to the decision');

    // --- UC-B4.1 · bob is not ready, so alice writes him legacy ------------
    final earlyKey = toBob(unique('treaty'));
    expect(
        await aliceClient.put(earlyKey, 'sent while bob was not ready'), true);
    expect((await aliceClient.get(earlyKey)).metadata?.appMetadata?.providerId,
        legacyCryptoProviderId,
        reason: 'bob has published a namespace key and alice could seal to it '
            '— his marker is the only thing stopping her, because one of his '
            'enrollments may still be an old build');

    // --- UC-B4.4 · bob finishes upgrading and declares readiness -----------
    await AtClientManager.getInstance().setCurrentAtSign(
        bob, namespace, TestPreferences.getInstance().getPreference(bob));
    await bobRollout.declareReady(pqNamespace);
    await E2ESyncService.getInstance().syncData(bobClient.syncService);

    await AtClientManager.getInstance().setCurrentAtSign(
        alice, namespace, TestPreferences.getInstance().getPreference(alice));

    expect(await CryptoRollout(aliceClient).advertisedBy(bob, pqNamespace),
        containsAll([nskeyCryptoProviderId, symmetricAesGcmCryptoProviderId]),
        reason: 'and she must see the flip — the two arms differ in this read '
            'and nothing else');

    final readyKey = toBob(unique('treaty'));
    expect(await aliceClient.put(readyKey, 'sent once bob was ready'), true);
    final stamped = (await aliceClient.get(readyKey)).metadata?.appMetadata;
    expect(stamped?.providerId, symmetricAesGcmCryptoProviderId,
        reason: 'the same client that wrote legacy a moment ago now writes the '
            'nskey data path — nothing changed but a record on bob\'s '
            'atServer');
    expect(stamped?.additional?['ckKid'], isNotNull,
        reason: 'and the value cites a content key rather than carrying one');

    // --- UC-B4.3 · alice\'s own self copy is a separate negotiation --------
    // Same client, same namespace, same put — but this record is read by
    // ALICE's fleet, which has not declared readiness.
    final selfKey = AtKey()
      ..key = unique('diary')
      ..namespace = pqNamespace
      ..sharedBy = alice;
    expect(await aliceClient.put(selfKey, 'for alice only'), true);
    expect((await aliceClient.get(selfKey)).metadata?.appMetadata?.providerId,
        legacyCryptoProviderId,
        reason: 'two directions, two schemes, one client: bob being ready must '
            'not decide what alice writes for her own enrollments, one of '
            'which may still be legacy-only');

    await E2ESyncService.getInstance().syncData(aliceClient.syncService);

    // --- and bob can actually read what she negotiated ---------------------
    await AtClientManager.getInstance().setCurrentAtSign(
        bob, namespace, TestPreferences.getInstance().getPreference(bob));
    await E2ESyncService.getInstance().syncData(bobClient.syncService);

    final received = await bobClient.get(AtKey()
      ..key = readyKey.key
      ..namespace = pqNamespace
      ..sharedWith = bob
      ..sharedBy = alice);
    expect(received.value, 'sent once bob was ready',
        reason: 'negotiating the post-quantum path is only correct if the '
            'recipient it was negotiated with can open the result');

    // The record written before the flip still opens too — a flip is not
    // retroactive, and reads stay universal.
    final early = await bobClient.get(AtKey()
      ..key = earlyKey.key
      ..namespace = pqNamespace
      ..sharedWith = bob
      ..sharedBy = alice);
    expect(early.value, 'sent while bob was not ready');
  });
}
