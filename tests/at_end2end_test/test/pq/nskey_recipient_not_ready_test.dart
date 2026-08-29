// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// Sharing with a recipient who has not enabled the namespace.
///
/// There is no PQ fallback to reach for here. `@bob`'s signing root is a
/// *verification* key — nothing is ever encapsulated to it — so an atSign with
/// no published nskey for a namespace has no post-quantum path at all, and the
/// send has to fail rather than quietly degrade.
///
/// What the row asks for beyond "it fails" is the part that matters to an app:
/// the failure must name **who** and **which namespace**, so the app can say
/// "@bob hasn't enabled this yet" instead of showing an encryption error; and
/// there must be a way to ask the same question *before* the user composes
/// anything, rather than discovering it on send.
///
/// Both namespaces are unique per run, so `@bob` has genuinely never used or
/// authorised either one, and this file establishes every fact it asserts.
///
/// ⚠️ **The control used to ask about the shared `e2e_test` namespace, and
/// that made this file depend on another one.** Nothing here put @bob in nskey
/// mode, and the e2e preferences configure no crypto, so @bob never mints on
/// his own — the control only answered "yes" when one of `era_default_read`,
/// `nskey_notify` or `nskey_cross_atsign` had already minted his `e2e_test`
/// key. `dart test` does not order files alphabetically: run alone, or first
/// in the directory as CI happened to run it, the control failed and took the
/// whole use case down with it. The control now mints its own yes-case.
void main() {
  late String alice;
  late String bob;
  late String authType;
  final namespace = TestConstants.namespace;

  /// A namespace nobody has minted for, on either atSign.
  final coldNamespace = 'cold${DateTime.now().microsecondsSinceEpoch}';

  /// A namespace @bob HAS enabled — minted below, so the control's "yes" is
  /// this file's own doing rather than a side effect of whatever ran first.
  final warmNamespace = 'warm${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    authType = ConfigUtil.getYaml()['authType'];
  });

  test('UC-A4.2: a share to a recipient with no namespace key fails, naming '
      'them', () async {
    // Both atSigns live at once. @bob has to mint for himself, and under the
    // singleton bringing him up would tear alice's client down.
    final clients =
        await ConcurrentClients.open(alice, bob, namespace, authType,
            posture: legacyPlusPqProviders);
    addTearDown(clients.close);
    final aliceClient = clients.first;
    final bobClient = clients.second;

    final ring = PublishedNskeyKeyRing(aliceClient);
    aliceClient.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);

    // Alice mints for the cold namespace herself. Without this the write would
    // fail for HER missing key (UC-A3.3) and this test would pass for the
    // wrong reason — it must be bob's absence that stops it.
    await ring.mintAndPublish(coldNamespace);

    // @bob enables the warm namespace and nothing else. This is the control's
    // premise, established here rather than inherited.
    final bobRing = PublishedNskeyKeyRing(bobClient);
    bobClient.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: bobRing);
    await bobRing.mintAndPublish(warmNamespace);
    await E2ESyncService.getInstance()
        .syncData(bobClient.syncService, atSign: bob);

    // Checked, not assumed: bob really has nothing published here. If he did,
    // the send below would succeed and there would be no failure to inspect.
    expect(await ring.currentPublic(bob, coldNamespace), isNull,
        reason: 'the premise is that @bob has never used or authorised this '
            'namespace; if he has a key, this tests nothing');

    // The pre-flight question, asked before anything is composed. An app that
    // asks first can say "@bob hasn't enabled this yet" up front.
    expect(await CryptoRuntime(aliceClient).isReadyFor(bob, coldNamespace),
        isFalse,
        reason: 'the readiness query must answer the same question the send '
            'is about to answer the hard way — that is the whole point of it '
            'existing');

    // Control: the same query for the namespace bob just enabled answers true,
    // so the false above is about that namespace rather than a query that
    // always says no.
    expect(await CryptoRuntime(aliceClient).isReadyFor(bob, warmNamespace),
        isTrue,
        reason: 'control: readiness must be able to say yes, or its "no" '
            'carries no information');

    final shared = AtKey()
      ..key = 'invite${DateTime.now().microsecondsSinceEpoch}'
      ..namespace = coldNamespace
      ..sharedWith = bob
      ..sharedBy = alice;

    // The send. It must fail, and the failure must be diagnosable: an app
    // showing a generic encryption error here cannot tell its user what to do.
    await expectLater(
        aliceClient.put(shared, 'an invitation bob cannot yet receive'),
        throwsA(predicate((e) =>
            '$e'.contains(bob) && '$e'.contains(coldNamespace))),
        reason: 'the exception must name the recipient AND the namespace. '
            'Bob\'s signing root cannot stand in — it is a verification key '
            'and receives no encapsulation — so there is nothing to fall back '
            'to and the app has to be told precisely what is missing');
  });
}
