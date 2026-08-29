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

/// A share read by more than one of the recipient's enrollments, written by
/// more than one of the sender's.
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

  /// Distinguishes this run's device names. An enrollment is one-shot per
  /// `(appName, deviceName)` — a second run reusing a name is refused by the
  /// atServer, not silently reused — so a fixed name would pass once.
  final runStamp = DateTime.now().microsecondsSinceEpoch;

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final authType = ConfigUtil.getYaml()['authType'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(alice, namespace, authType, posture: PqPosture.legacy);
    await TestSuiteInitializer.getInstance()
        .testInitializer(bob, namespace, authType, posture: PqPosture.legacy);
  });

  // Named as one string literal on purpose: `provenIn` matches a citation
  // against the SOURCE, and adjacent literals the compiler would join are not
  // contiguous there — a split name reads to it as a renamed test.
  test(
      'UC-A4.3: whichever alice enrollment writes, every bob enrollment reads',
      () async {
    // Both atSigns live at once, each with its own AtClientManager. Through
    // the singleton, bringing alice up would tear bob's client down — his
    // syncService is unset the moment the manager moves off him — and the
    // failure would surface much later, far from its cause.
    final clients = await ConcurrentClients.open(
        alice, bob, sharedNamespace, ConfigUtil.getYaml()['authType'],
            posture: PqPosture.legacy);
    final aliceClient = clients.first;
    final bobPrimary = clients.second;

    final bobPreference = bobPrimary.getPreferences()!;
    final bobRing = PublishedNskeyKeyRing(bobPrimary);
    bobPrimary.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: bobRing);
    final bobAdvertised = await bobRing.mintAndPublish(sharedNamespace);
    await E2ESyncService.getInstance()
        .syncData(bobPrimary.syncService, atSign: bob);

    // The approver seals the enrollee's symmetric key to its own key package,
    // so it must have one registered before it can approve anything. Both
    // atSigns approve an enrollment below, so both register.
    await AtClientSecretSharing.forClient(bobPrimary).register();
    await AtClientSecretSharing.forClient(aliceClient).register();

    // A second enrollment of @bob, genuinely distinct: its own enrollment id,
    // its own APKAM keypair, its own client.
    final bobSecond = await enrolAndAuthenticate(
      approver: bobPrimary,
      atSign: bob,
      namespace: sharedNamespace,
      preference: TestPreferences.getInstance().getPreference(bob,
          posture: PqPosture.legacy),
      rootDomain: bobPreference.rootDomain,
      rootPort: bobPreference.rootPort,
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

    // ── The sending side, varied ─────────────────────────────────────────
    //
    // Everything above holds alice fixed and varies bob. The clause also says
    // "whichever of alice's enrollments wrote it", which is a claim about the
    // SENDER: readability follows @bob's namespace key, so it cannot depend on
    // which of alice's enrollments did the sealing. Nothing establishes that
    // until a second alice client writes the same kind of record.
    final alicePreference = aliceClient.getPreferences()!;
    final aliceSecond = await enrolAndAuthenticate(
      approver: aliceClient,
      atSign: alice,
      namespace: sharedNamespace,
      // A store of its own, unlike bobSecond above. It matters here and not
      // there: a content key is a client-side cache, so an alice2 sharing
      // alice1's store could seal with the key alice1 already minted and this
      // would be alice1's conveyance under a second name. bobSecond needs no
      // such separation — nskey privates are filed through `AtKeysIo`, and its
      // enrollment carries an in-memory one of its own, so it cannot inherit
      // bob's namespace private through a shared store either way.
      preference: TestPreferences.getInstance().forCoLocatedClient(alice,
          posture: PqPosture.legacy, device: 'alice2-$runStamp'),
      rootDomain: alicePreference.rootDomain,
      rootPort: alicePreference.rootPort,
      deviceName: 'alice2-$runStamp',
    );

    expect(aliceSecond.client.enrollmentId, isNotNull,
        reason: 'the sender must genuinely be an enrollment, or "whichever of '
            'alice\'s enrollments wrote it" is not what varied');
    expect(aliceSecond.client.enrollmentId, isNot(aliceClient.enrollmentId),
        reason: 'and a different one from the client that wrote the first '
            'record');

    // alice2 mints NOTHING for itself. A sender seals to the recipient's
    // published namespace key, so it needs no generation of its own — and
    // asserting that by not providing one is stronger than asserting it in
    // prose.
    final aliceSecondRing = PublishedNskeyKeyRing(aliceSecond.client);
    aliceSecond.client.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: aliceSecondRing);

    final secondKeyName = 'multishare2${DateTime.now().microsecondsSinceEpoch}';
    const secondPlaintext = 'written by alice\'s other enrollment';
    AtKey fromAliceSecond() => AtKey()
      ..key = secondKeyName
      ..namespace = sharedNamespace
      ..sharedWith = bob
      ..sharedBy = alice;

    expect(await aliceSecond.client.put(fromAliceSecond(), secondPlaintext),
        true);
    await E2ESyncService.getInstance()
        .syncData(aliceSecond.client.syncService, atSign: alice);

    final secondAsWritten = await aliceSecond.client.get(fromAliceSecond());
    expect(secondAsWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'alice2 must be on the same nskey data path as alice1, or the '
            'two records differ in more than the enrollment that wrote them');
    final secondConveyanceKid =
        secondAsWritten.metadata?.appMetadata?.additional?['ckKid'];
    expect(secondConveyanceKid, isNotNull);
    expect(secondConveyanceKid, isNot(conveyanceKid),
        reason: 'alice2 sealed a content key of its own. Had this matched, the '
            'record would be carrying alice1\'s conveyance and the sending '
            'side would not have varied at all');

    // Both of @bob's enrollments read the record alice's OTHER enrollment
    // wrote — which is the clause, in full.
    await E2ESyncService.getInstance()
        .syncData(bobPrimary.syncService, atSign: bob);
    expect((await bobPrimary.get(fromAliceSecond())).value, secondPlaintext,
        reason: 'the enrollment that minted the namespace key reads what '
            'alice2 sealed to it');
    expect(
        (await bobSecond.client.get(fromAliceSecond())).value, secondPlaintext,
        reason: 'and so does bob\'s second enrollment. No authorised '
            'enrollment on the receiving side is left unable to decrypt, and '
            'it did not matter which of alice\'s enrollments wrote the '
            'record — the seal is to (owner, namespace) on the RECIPIENT side '
            'and carries no sender identity a reader has to hold');
  }, timeout: Timeout(Duration(minutes: 5)));
}
