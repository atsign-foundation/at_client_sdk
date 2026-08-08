// The nskey and enrollment surfaces are @experimental; driving them from
// another package is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/src/enrolled_client.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// A share read by more than one of the recipient's enrollments.
///
/// The property under test is that readability follows the **namespace key**,
/// not the enrollment. A content key is sealed once, to `(owner, namespace)` —
/// `recipientKind: nskey` — so every enrollment of that atSign holding the
/// namespace private opens it, and adding a device costs the sender nothing.
/// Had the design sealed per enrollment instead, a sender would have to know
/// the recipient's device list and re-seal whenever it changed, and a device
/// approved after the send could never read what came before it.
///
/// Two things make this testable at all, both landed today: the enrollment
/// fixture, and keying `AtClientImpl`'s instance cache by
/// `(atSign, enrollmentId)` — before that, two "enrollments" of one atSign were
/// the same client object and this would have read one client twice.
void main() {
  late String alice;
  late String bob;
  final namespace = TestConstants.namespace;

  /// Unique per run: @bob mints for it here, so it must not carry a key from
  /// an earlier run or the conveyance below proves nothing.
  final sharedNamespace = 'multi${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final authType = ConfigUtil.getYaml()['authType'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(alice, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(bob, namespace, authType);
  });

  test('UC-A4.3: every authorised enrollment of the recipient reads the share',
      () async {
    // Both atSigns live at once, each with its own AtClientManager. Through
    // the singleton, bringing alice up would tear bob's client down — his
    // syncService is unset the moment the manager moves off him — and the
    // failure would surface much later, far from its cause.
    final clients = await ConcurrentClients.open(
        alice, bob, sharedNamespace, ConfigUtil.getYaml()['authType']);
    final aliceClient = clients.first;
    final bobPrimary = clients.second;

    final bobPreference = bobPrimary.getPreferences()!;
    final bobRing = PublishedNskeyKeyRing(bobPrimary);
    bobPrimary.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: bobRing);
    final bobAdvertised = await bobRing.mintAndPublish(sharedNamespace);
    await E2ESyncService.getInstance()
        .syncData(bobPrimary.syncService, atSign: bob);

    // The approver seals the enrollee's symmetric key to its own key package,
    // so it must have one registered before it can approve anything.
    await AtClientSecretSharing.forClient(bobPrimary).register();

    // A second enrollment of @bob, genuinely distinct: its own enrollment id,
    // its own APKAM keypair, its own client.
    final bobSecond = await enrolAndAuthenticate(
      approver: bobPrimary,
      atSign: bob,
      namespace: sharedNamespace,
      preference: TestPreferences.getInstance().getPreference(bob),
      rootDomain: bobPreference.rootDomain!,
      rootPort: bobPreference.rootPort!,
      deviceName: 'bob2-${DateTime.now().microsecondsSinceEpoch}',
    );

    expect(identical(bobSecond.client, bobPrimary), isFalse,
        reason: 'the second enrollment must be a genuinely different client, '
            'or this reads one client twice and proves nothing about '
            'enrollments');

    // Alice seals to @bob's namespace key — once, to the namespace, with no
    // knowledge of how many devices @bob runs.
    final aliceRing = PublishedNskeyKeyRing(aliceClient);
    aliceClient.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: aliceRing);
    await aliceRing.mintAndPublish(sharedNamespace);

    final keyName = 'multishare${DateTime.now().microsecondsSinceEpoch}';
    const plaintext = 'readable by every device bob has authorised';
    final shared = AtKey()
      ..key = keyName
      ..namespace = sharedNamespace
      ..sharedWith = bob
      ..sharedBy = alice;

    expect(await aliceClient.put(shared, plaintext), true);
    await E2ESyncService.getInstance()
        .syncData(aliceClient.syncService, atSign: alice);

    // Verified rather than assumed: alice really wrote the PQ scheme. A legacy
    // write would be readable by both enrollments for entirely different
    // reasons and this test would pass for the wrong one.
    final asWritten = await aliceClient.get(shared);
    expect(asWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the share must be on the nskey data path for the rest of this '
            'to be about namespace-scoped readability');

    // The structural claim, read off the record: the content key was sealed to
    // a NAMESPACE key, naming the generation @bob published — not to any
    // enrollment or key package. That is why enrollment count is irrelevant.
    final conveyanceKid = asWritten.metadata?.appMetadata?.additional?['ckKid'];
    expect(conveyanceKid, isNotNull);
    // Read off the wire rather than through get()/getMeta(), both of which
    // decrypt — and alice cannot open this conveyance, correctly: it is sealed
    // to @bob's namespace key, not hers. What is being inspected is the
    // metadata, which is atServer-visible plaintext by design, so asking the
    // atServer for it directly is both possible and the more faithful check.
    final metaResponse = await aliceClient.getRemoteSecondary()!.executeCommand(
        'llookup:meta:$bob:$conveyanceKid.__ck.$sharedNamespace$alice\n',
        auth: true);
    expect(metaResponse, isNotNull);
    final appMetadataRaw = jsonDecode(
        metaResponse!.replaceFirst('data:', '').trim())['appMetadata'];
    expect(appMetadataRaw, isNotNull,
        reason: 'the conveyance must carry its routing metadata on the '
            'atServer, or no reader can tell what it was sealed to');
    // `llookup:meta:` returns appMetadata already decoded; the update fragment
    // carries it base64-encoded. Accept either rather than pinning this test
    // to one representation of a field it does not own.
    final envelope = (appMetadataRaw is String
        ? jsonDecode(utf8.decode(base64Decode(appMetadataRaw)))
        : appMetadataRaw) as Map<String, dynamic>;
    expect(envelope['recipientKind'], 'nskey',
        reason: 'sealed to the namespace, not to a device. If this were a key '
            'package id, a sender would need @bob\'s device list and a device '
            'approved later could never read what came before it');
    expect(envelope['nskeyKid'], bobAdvertised.nskeyKid,
        reason: 'and to the generation @bob actually advertised');

    AtKey inbound() => AtKey()
      ..key = keyName
      ..namespace = sharedNamespace
      ..sharedWith = bob
      ..sharedBy = alice;

    // Both of @bob's enrollments read the same record.
    await E2ESyncService.getInstance()
        .syncData(bobPrimary.syncService, atSign: bob);
    expect((await bobPrimary.get(inbound())).value, plaintext,
        reason: 'the enrollment that minted the namespace key reads it');

    expect((await bobSecond.client.get(inbound())).value, plaintext,
        reason: 'and so does the second enrollment — it holds the same '
            'namespace private, which is the whole point of scoping the seal '
            'to (owner, namespace) rather than to a device');
  });
}
