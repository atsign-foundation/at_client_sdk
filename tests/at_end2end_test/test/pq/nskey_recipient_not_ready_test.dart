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
/// There is no PQ fallback to reach for. `@bob`'s signing root is a
/// *verification* key — nothing is ever encapsulated to it — so an atSign with
/// no published nskey for a namespace has no post-quantum path at all, and the
/// send has to fail rather than quietly degrade. The failure must name **who**
/// and **which namespace**, so an app can say "@bob hasn't enabled this yet"
/// instead of showing an encryption error, and the same question must be
/// answerable before the user composes anything rather than only on send.
///
/// Both namespaces are unique per run, so `@bob` has genuinely never used or
/// authorised either one, and this file establishes every fact it asserts —
/// including the control's yes-case, which otherwise depends on whichever
/// sibling file happened to run first.
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

  test(
      'UC-A4.2: a share to a recipient with no namespace key fails, naming '
      'them', () async {
    // NOTE: both atSigns must be live at once — @bob mints for himself, and
    // under the singleton bringing him up would tear alice's client down.
    final clients = await ConcurrentClients.open(
        alice, bob, namespace, authType,
        posture: legacyPlusPqProviders);
    addTearDown(clients.close);
    final aliceClient = clients.first;
    final bobClient = clients.second;

    final ring = PublishedNskeyKeyRing(aliceClient);
    aliceClient.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);

    // NOTE: alice mints for the cold namespace herself, or the write fails for
    // HER missing key (UC-A3.3) and the test passes for the wrong reason — it
    // must be bob's absence that stops it.
    await ring.mintAndPublish(coldNamespace);

    final bobRing = PublishedNskeyKeyRing(bobClient);
    bobClient.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: bobRing);
    await bobRing.mintAndPublish(warmNamespace);
    await E2ESyncService.getInstance()
        .syncData(bobClient.syncService, atSign: bob);

    expect(await ring.currentPublic(bob, coldNamespace), isNull,
        reason: 'the premise is that @bob has never used or authorised this '
            'namespace; if he has a key, this tests nothing');

    expect(await CryptoRuntime(aliceClient).isReadyFor(bob, coldNamespace),
        isFalse,
        reason: 'the readiness query must answer the same question the send '
            'is about to answer the hard way — that is the whole point of it '
            'existing');

    expect(
        await CryptoRuntime(aliceClient).isReadyFor(bob, warmNamespace), isTrue,
        reason: 'control: readiness must be able to say yes, or its "no" '
            'carries no information');

    final shared = AtKey()
      ..key = 'invite${DateTime.now().microsecondsSinceEpoch}'
      ..namespace = coldNamespace
      ..sharedWith = bob
      ..sharedBy = alice;

    await expectLater(
        aliceClient.put(shared, 'an invitation bob cannot yet receive'),
        throwsA(predicate(
            (e) => '$e'.contains(bob) && '$e'.contains(coldNamespace))),
        reason: 'the exception must name the recipient AND the namespace. '
            'Bob\'s signing root cannot stand in — it is a verification key '
            'and receives no encapsulation — so there is nothing to fall back '
            'to and the app has to be told precisely what is missing');
  });
}
