@Tags(['pq'])
library;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-A5.1(a) — coarse forward secrecy by rotating the content key, driven end
/// to end against a live atServer.
///
/// Cutting a fresh content key and deleting the conveyance record carrying the
/// old one leaves data written under it undecryptable by design, which is why
/// the assertion below is a failure to read.
void main() {
  TestUtils.isolateStorage('content_key_rotation_live_test');
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

    // NOTE: the era default writes legacy, so the value this scenario rotates
    // needs the PQ providers named explicitly.
    final preference =
        TestUtils.getPreference(atSign, posture: legacyPlusPqProviders)
          ..crypto = CryptoConfig.nskey(keyRing: ring);

    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        preference: preference, posture: legacyPlusPqProviders);
    atClient = atClientManager.atClient;

    // NOTE: the manager the providers were wired with, so the rotation runs
    // over the same content-key cache the reads consult. A second CkManager
    // built here evicts from a cache nobody reads, and the assertions pass for
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

    // NOTE: control arm — without it the failure after the rotation is equally
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

    // NOTE: the delete has to reach the atServer — until it syncs, every
    // other client can still unwrap the old content key.
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

    await expectLater(
        atClient.get(early), throwsA(isA<AtDecryptionException>()),
        reason: 'the nskey private is intact and still opens everything else '
            'in this namespace; what is gone is the one record that carried '
            'this content key, and no later repair brings the data back');

    // Writing still works: forward secrecy that also broke the destination
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
