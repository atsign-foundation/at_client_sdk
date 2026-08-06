import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-A5.1(a) — coarse forward secrecy by rotating the **content key**, driven
/// end to end against a live atServer.
///
/// This is the cheap lever and the only one of the two that reaches data
/// already written: cut a fresh CK, and delete the conveyance record carrying
/// the old one. From then on nothing can unwrap it — the namespace's nskey
/// private cannot help, because no sealed copy of that CK survives anywhere.
/// Data written under it is undecryptable **by design**, which is the whole
/// point and is why the assertion below is a *failure* to read.
///
/// Rotating the nskey **keypair** does none of this: it denies an enrollment
/// the keys protecting future data and leaves every earlier CK readable
/// (`nskey_rotation_live_test.dart`). The two levers are not substitutes, and
/// the cost difference is O(1) against O(n)-per-enrollment.
void main() {
  late AtClientManager atClientManager;
  late AtClient atClient;
  late String atSign;
  late CkManager ckManager;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];

    final nskeyPair = await XWingKeyPair.generate();
    final ring = InMemoryNskeyKeyRing()
      ..seedKeypair(atSign, namespace,
          publicKey: nskeyPair.publicKeyBytes,
          privateKey: nskeyPair.privateKeyBytes);

    // Writes go out on the nskey data path, not legacy — the era default reads
    // PQ and writes legacy, and this scenario is about a PQ-written value.
    final preference = TestUtils.getPreference(atSign)
      ..crypto = CryptoConfig.nskey(keyRing: ring);

    atClientManager =
        await TestUtils.initAtClient(atSign, namespace, preference: preference);
    atClient = atClientManager.atClient;

    // The manager the providers were wired with, so the rotation runs over the
    // SAME content-key cache the reads consult. A second CkManager built here
    // would evict from a cache nobody reads, and the assertion would pass for
    // the wrong reason.
    ckManager = (CryptoConfig.forClient(atClient)
            .lookup(symmetricAesGcmCryptoProviderId) as SymmetricAesGcmProvider)
        .ckManager!;
  });

  test('deleting the superseded conveyance makes its era undecryptable',
      () async {
    final early = AtKey()
      ..key = 'treaty-early'
      ..namespace = namespace
      ..sharedBy = atSign;
    const earlyText = 'written under the first content key';

    expect(await atClient.put(early, earlyText), true);

    // Control arm. Without it, the failure after the rotation is equally
    // explained by a value that never decrypted in the first place.
    final beforeRotation = await atClient.get(early);
    expect(beforeRotation.value, earlyText);
    final supersededCkKid =
        beforeRotation.metadata?.appMetadata?.additional?['ckKid'] as String?;
    expect(supersededCkKid, isNotNull);

    final successor = await ckManager.rotateContentKey(
        CryptoContext(atClient: atClient), early,
        deleteSuperseded: true);
    expect(successor.ckKid, isNot(supersededCkKid));

    // The record that carried the old CK is gone from the atServer, not merely
    // from this device — a local-only delete would leave every other client
    // able to unwrap it at its next sync.
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: atClient.syncService, label: 'ck-rotation');
    await expectLater(
        atClient.getRemoteSecondary()!.executeCommand(
            'llookup:$supersededCkKid.__ck.$namespace$atSign\n',
            auth: true),
        throwsA(anything),
        reason: 'deletion is the trusted-computing base of coarse forward '
            'secrecy — while the conveyance is servable, anyone authorised '
            'for the namespace can unwrap the CK again');

    // And the old value no longer reads. This is the property, and it is
    // supposed to look like a failure.
    await expectLater(
        atClient.get(early), throwsA(isA<AtDecryptionException>()),
        reason: 'the nskey private is intact and still opens everything else '
            'in this namespace; what is gone is the one record that carried '
            'this content key, and no later repair brings the data back');

    // The destination still works. Forward secrecy that also broke writing
    // would be a bug wearing a security property's name.
    final later = AtKey()
      ..key = 'treaty-later'
      ..namespace = namespace
      ..sharedBy = atSign;
    const laterText = 'written under the successor';
    expect(await atClient.put(later, laterText), true);
    final readBack = await atClient.get(later);
    expect(readBack.value, laterText);
    expect(
        readBack.metadata?.appMetadata?.additional?['ckKid'], successor.ckKid);
  });

  test('rotating without the delete keeps the era readable — the default',
      () async {
    final retained = AtKey()
      ..key = 'treaty-retained'
      ..namespace = namespace
      ..sharedBy = atSign;
    const text = 'written under a CK that is superseded but not deleted';

    expect(await atClient.put(retained, text), true);
    final ckKid = (await atClient.get(retained))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'] as String?;

    final successor = await ckManager.rotateContentKey(
        CryptoContext(atClient: atClient), retained);
    expect(successor.ckKid, isNot(ckKid));

    expect((await atClient.get(retained)).value, text,
        reason: 'retention is the DEFAULT, and it is what lets a '
            'late-joining enrollment read history — forward secrecy is opt '
            'in, per rotation, because it destroys data');
  });
}
