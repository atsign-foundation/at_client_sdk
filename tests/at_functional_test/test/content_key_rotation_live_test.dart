@Tags(['pq'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
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
  late InMemoryNskeyKeyRing ring;
  late AtClientPreference preference;
  const namespace = 'wavi';

  CkManager managerOf(AtClient client) =>
      (CryptoConfig.forClient(client).lookup(symmetricAesGcmCryptoProviderId)
              as SymmetricAesGcmProvider)
          .ckManager!;

  /// Whether the atServer still serves the self conveyance carrying [ckKid].
  Future<bool> served(String ckKid) async {
    try {
      await atClient.getRemoteSecondary()!.executeCommand(
          'llookup:$ckKid.__ck.$namespace$atSign\n',
          auth: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> sync(String label) => FunctionalTestSyncService.getInstance()
      .syncData(syncSvc: atClient.syncService, label: label);

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];

    final nskeyPair = await XWingKeyPair.generate();
    ring = InMemoryNskeyKeyRing()
      ..seedKeypair(atSign, namespace,
          publicKey: nskeyPair.publicKeyBytes,
          privateKey: nskeyPair.privateKeyBytes);

    // NOTE: the era default writes with the legacy provider, so the value this
    // scenario rotates needs the PQ providers named explicitly.
    preference = TestUtils.getPreference(atSign, posture: legacyPlusPqProviders)
      ..crypto = CryptoConfig.nskey(keyRing: ring);

    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        preference: preference, posture: legacyPlusPqProviders);
    atClient = atClientManager.atClient;

    // NOTE: the manager the providers were wired with, so the rotation runs
    // over the same content-key cache the reads consult. A second CkManager
    // built here evicts from a cache nobody reads, and the assertions pass for
    // the wrong reason.
    ckManager = managerOf(atClient);
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

  test(
      'a superseded key is kept while a record cites it, and collected once '
      'none does', () async {
    final first = AtKey()
      ..key = 'treaty-collected'
      ..namespace = namespace
      ..sharedBy = atSign;
    expect(await atClient.put(first, 'cites the first key'), true);
    final superseded = (await atClient.get(first))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'] as String;
    final context = CryptoContext(atClient: atClient);

    final successor = await ckManager.rotateContentKey(context, first);
    await ckManager.idle;
    await sync('ck-collect-rotated');
    expect(await served(superseded), isTrue,
        reason: 'the rotation\'s own collection keeps a key a record cites');

    expect(await atClient.delete(first), true);
    await sync('ck-collect-uncited');
    expect(await ckManager.collectUnused(context), 1,
        reason: 'nothing cites it now, and this enrollment cut it');
    await sync('ck-collect-deleted');

    expect(await served(superseded), isFalse,
        reason: 'the deletion reached the atServer');
    expect(await served(successor.ckKid), isTrue,
        reason: 'the current key is kept although nothing cites it yet');
  });

  test('a start collects, once sync has caught up, a key nothing cites',
      () async {
    // A cut that stopped after its conveyance and before its pointer: sealed
    // by this enrollment, named by no pointer, cited by nothing. Written to
    // the atServer directly, and the client stopped at once, so no collection
    // this client already has pending takes it first.
    final orphan =
        ContentKey(Uint8List.fromList(base64Decode(AESKey.generate(32).key)));
    expect(
        await atClient.put(
            AtKey()
              ..key = '${orphan.ckKid}.__ck'
              ..namespace = namespace
              ..sharedBy = atSign,
            orphan.toBase64(),
            putRequestOptions: PutRequestOptions()
              ..cryptoProviderId = nskeyCryptoProviderId
              ..useRemoteAtServer = true),
        true);
    expect(await served(orphan.ckKid), isTrue,
        reason: 'the control: it is on the atServer before the restart');
    final current = CryptoConfig.forClient(atClient)
        .contentKeyCache
        ?.current(atSign, namespace)
        ?.ckKid;

    // A restart: a new client over the same storage, and a fresh crypto
    // configuration holding nothing in memory, so only the synced pointer
    // names the current key.
    await atClient.stop();
    preference.crypto = CryptoConfig.nskey(keyRing: ring);
    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        preference: preference, posture: legacyPlusPqProviders);
    atClient = atClientManager.atClient;
    ckManager = managerOf(atClient);

    var collected = false;
    for (var attempt = 0; attempt < 20 && !collected; attempt++) {
      await sync('ck-restart-$attempt');
      collected = !await served(orphan.ckKid);
      if (!collected) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    expect(collected, isTrue,
        reason: 'the restarted client collects once its sync has caught up');
    if (current != null) {
      expect(await served(current), isTrue,
          reason: 'the key its pointer names is kept, with nothing in memory');
    }
  });

  // NOTE: last in the file, since it leaves a policy that replaces the key at
  // every write.
  test('a key the policy replaces is collected at the next caught-up sync',
      () async {
    preference.crypto =
        CryptoConfig.nskey(keyRing: ring, ckRotationPolicy: (_) async => true);
    String ckKidOf(AtValue value) =>
        value.metadata!.appMetadata!.additional!['ckKid'] as String;

    final first = AtKey()
      ..key = 'treaty-policy-first'
      ..namespace = namespace
      ..sharedBy = atSign;
    expect(await atClient.put(first, 'cites the key in use'), true);
    final superseded = ckKidOf(await atClient.get(first));
    expect(await atClient.delete(first), true);
    await sync('ck-policy-uncited');

    final second = AtKey()
      ..key = 'treaty-policy-second'
      ..namespace = namespace
      ..sharedBy = atSign;
    expect(await atClient.put(second, 'written under the successor'), true);
    final successor = ckKidOf(await atClient.get(second));
    expect(successor, isNot(superseded),
        reason: 'the control: the policy replaced the key');

    var collected = false;
    for (var attempt = 0; attempt < 20 && !collected; attempt++) {
      await sync('ck-policy-$attempt');
      collected = !await served(superseded);
      if (!collected) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    expect(collected, isTrue,
        reason: 'the replacement\'s collection is refused while its own '
            'writes push, and runs at the next sync that catches up');
    expect(await served(successor), isTrue);
  });
}
