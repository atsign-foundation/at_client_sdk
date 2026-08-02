import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
// ignore: implementation_imports
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
// ignore: implementation_imports
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// The nskey data path across two real atSigns.
///
/// This is the case the original providers got wrong, and the reason the whole
/// design was re-examined: on an inbound record the *record* belongs to the
/// sender but the envelope is sealed to the **recipient's** nskey, so deriving
/// the key from `sharedBy` made a reader ask its ring for the sender's namespace
/// private — which it will never hold. Self data hides the bug entirely, because
/// there the two atSigns coincide. Only two atSigns can prove it is fixed.
void main() {
  late String alice;
  late String bob;
  final namespace = TestConstants.namespace;

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final authType = ConfigUtil.getYaml()['authType'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(alice, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(bob, namespace, authType);
  });

  /// Bring an atSign up on the nskey data path, minting and publishing its
  /// namespace key. The ring needs the client, and the client's preference is
  /// read live, so the config is set once both exist.
  Future<({AtClient client, PublishedNskeyKeyRing ring})> nskeyClient(
      String atSign) async {
    final preference = TestPreferences.getInstance().getPreference(atSign);
    final manager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, namespace, preference);
    final client = manager.atClient;

    final ring = PublishedNskeyKeyRing(client);
    client.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    await ring.mintAndPublish(namespace);
    await E2ESyncService.getInstance().syncData(client.syncService);
    return (client: client, ring: ring);
  }

  String uniqueKey(String prefix) =>
      '$prefix.${DateTime.now().microsecondsSinceEpoch}';

  // This test was skipped for a defect in at_client, not the atServer: the sync
  // PUSH dropped appMetadata, because SyncServiceImpl's hand-rolled metadata
  // serializer never emitted it. The record therefore reached the atServer
  // without a providerId, and @bob's lookup returned exactly what the server
  // held. CryptoRuntime then fell back to legacy and hunted for a shared_key a
  // PQ write never created. It affected EVERY provider's synced writes, not
  // just the PQ ones — see decisions.md section 17.
  //
  // Keeping this test cross-atSign is the point: the serializer has a unit test,
  // but only two atSigns prove the stamp survives the whole write path.
  test('alice shares with bob, and bob reads it with his own nskey private',
      () async {
    // Both sides mint and publish eagerly — no promotion step, so bob is
    // reachable the moment he has ever used the namespace.
    final bobSide = await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);

    final keyName = uniqueKey('treaty');
    const plaintext = 'the treaty text';
    final shared = AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;

    // Alice has no content key for @bob, so this only succeeds if the pre-pass
    // discovers bob's published nskey by plookup and conveys a CK sealed to it.
    expect(await aliceSide.client.put(shared, plaintext), true);
    await E2ESyncService.getInstance().syncData(aliceSide.client.syncService);

    // The value cites a CK and carries no key.
    final asWritten = await aliceSide.client.get(shared);
    final ckKid = asWritten.metadata?.appMetadata?.additional?['ckKid'];
    expect(asWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId);
    expect(ckKid, isNotNull);

    // Alice cannot open the conveyance she just wrote: it is sealed to BOB's
    // nskey and she holds no private for it. That is per-recipient scoping
    // working — if this ever succeeds, alice's own scope has been handed bob's
    // content key.
    await expectLater(
      aliceSide.client.get(AtKey()
        ..key = '$ckKid.__ck'
        ..namespace = namespace
        ..sharedWith = bob
        ..sharedBy = alice),
      throwsA(isA<AtException>()),
      reason: 'the sender must not be able to decapsulate a CK she sealed to '
          'the recipient — only bob can',
    );

    // Bob reads. This is the assertion the whole re-design turned on: the
    // record is alice-owned, so a reader keying its ring by sharedBy would look
    // up ALICE's private and fail. It resolves because the nskey owner is
    // sharedWith.
    await AtClientManager.getInstance().setCurrentAtSign(
        bob, namespace, TestPreferences.getInstance().getPreference(bob));
    await E2ESyncService.getInstance().syncData(bobSide.client.syncService);

    final received = await bobSide.client.get(AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice);
    expect(received.value, plaintext,
        reason: 'bob opens the CK with HIS nskey private, not the sender\'s');

    // And he opened it with the generation he had advertised — which is what
    // alice discovered by plookup rather than being told.
    expect(received.metadata?.appMetadata?.additional?['ckKid'], ckKid);
  });

  test('the sender keeps a self-copy under a different content key', () async {
    // Bob must have published his nskey before alice can seal a CK to it; the
    // handle itself is unused here.
    await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);

    final shared = AtKey()
      ..key = uniqueKey('memo')
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;
    expect(await aliceSide.client.put(shared, 'for bob'), true);

    final selfKey = AtKey()
      ..key = uniqueKey('memo')
      ..namespace = namespace
      ..sharedBy = alice;
    expect(await aliceSide.client.put(selfKey, 'for me'), true);

    final toBobCk = (await aliceSide.client.get(shared))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'];
    final selfCk = (await aliceSide.client.get(selfKey))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'];

    expect(toBobCk, isNot(selfCk),
        reason: 'content keys are scoped per recipient — bob\'s CK must never '
            'become the key alice encrypts her own data under, or holding one '
            'would open the other');
  });
}
