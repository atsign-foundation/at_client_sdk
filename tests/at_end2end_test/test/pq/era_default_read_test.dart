// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// A client that named **no** `CryptoConfig` decrypts an inbound PQ record.
///
/// This is the claim the era default exists to make, and it is the one a unit
/// test cannot reach: a mock never runs `AtClientImpl._init`, so an era default
/// that was never adopted passes every unit assertion, and the functional check
/// only shows the wiring arrived. Here bob is given nothing — no config, no
/// providers — and has to open a record alice sealed to his namespace key.
///
/// The asymmetry under test is the whole 3.x shape: alice must name
/// `CryptoConfig.nskey` to *write* PQ, because the era default deliberately
/// still writes legacy. Bob needs nothing to *read* it.
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

  Future<AtClient> clientFor(String atSign) async {
    final manager = await AtClientManager.getInstance().setCurrentAtSign(
        atSign, namespace, TestPreferences.getInstance().getPreference(atSign));
    return manager.atClient;
  }

  /// The key ring the SDK built for [client] as part of its era default —
  /// reached through the provider that holds it, so the test mints into the
  /// very ring the read path will consult rather than a lookalike.
  PublishedNskeyKeyRing eraKeyRing(AtClient client) {
    final config = CryptoConfig.forClient(client);
    final provider = config.lookup(nskeyCryptoProviderId);
    expect(provider, isA<NskeyProvider>(),
        reason: 'the era default must have registered the nskey provider, or '
            'there is no ring to reach and nothing below is being tested');
    return (provider as NskeyProvider).keyRing as PublishedNskeyKeyRing;
  }

  String uniqueKey(String prefix) =>
      '$prefix.${DateTime.now().microsecondsSinceEpoch}';

  test('bob, given no CryptoConfig at all, opens what alice sealed to him',
      () async {
    // Bob first: alice's pre-pass discovers his published nskey by plookup, so
    // it must exist before she writes. He mints through his OWN era ring, which
    // is the point — no config was ever handed to him.
    final bobClient = await clientFor(bob);
    expect(bobClient.getPreferences()?.crypto, isNull,
        reason: 'if the harness named a config, this test would be about the '
            'app\'s choice rather than the SDK\'s default');
    expect(CryptoConfig.forClient(bobClient).defaultProviderId,
        legacyCryptoProviderId,
        reason: 'and bob still WRITES legacy — reading is the only half the '
            'era default turns on');
    await eraKeyRing(bobClient).mintAndPublish(namespace);
    await E2ESyncService.getInstance()
        .syncData(bobClient.syncService, atSign: bob);

    // Alice has to opt in to WRITE pq — the era default would write legacy and
    // there would be no PQ record to read.
    final aliceClient = await clientFor(alice);
    final aliceRing = PublishedNskeyKeyRing(aliceClient);
    aliceClient.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: aliceRing);
    await aliceRing.mintAndPublish(namespace);

    final keyName = uniqueKey('erashare');
    const plaintext = 'opened with no config of my own';
    final shared = AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;

    expect(await aliceClient.put(shared, plaintext), true);
    await E2ESyncService.getInstance()
        .syncData(aliceClient.syncService, atSign: alice);

    // Verified, not assumed: alice really did write the PQ scheme. Without this
    // a legacy write would sail through the read below and the test would pass
    // for the wrong reason.
    final asWritten = await aliceClient.get(shared);
    expect(asWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'alice must have written the nskey data path for bob\'s side '
            'to be a test of reading it');

    final bobAgain = await clientFor(bob);
    await E2ESyncService.getInstance()
        .syncData(bobAgain.syncService, atSign: bob);

    final received = await bobAgain.get(AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice);

    expect(received.value, plaintext,
        reason: 'bob named no CryptoConfig; the SDK\'s era default supplied '
            'the providers, and his own nskey private opened the content key');
  });
}
