// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
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
/// The namespace is unique per run, so `@bob` has genuinely never used or
/// authorised it. Against a shared namespace he would already have a published
/// key from another test and the send would simply succeed, proving nothing.
void main() {
  late String alice;
  late String bob;
  final namespace = TestConstants.namespace;

  /// A namespace nobody has minted for, on either atSign.
  final coldNamespace = 'cold${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final authType = ConfigUtil.getYaml()['authType'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(alice, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(bob, namespace, authType);
  });

  test('UC-A4.2: a share to a recipient with no namespace key fails, naming '
      'them', () async {
    final preference = TestPreferences.getInstance().getPreference(alice);
    final manager = await AtClientManager.getInstance()
        .setCurrentAtSign(alice, namespace, preference);
    final aliceClient = manager.atClient;

    final ring = PublishedNskeyKeyRing(aliceClient);
    aliceClient.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);

    // Alice mints for the cold namespace herself. Without this the write would
    // fail for HER missing key (UC-A3.3) and this test would pass for the
    // wrong reason — it must be bob's absence that stops it.
    await ring.mintAndPublish(coldNamespace);

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

    // Control: the same query for a namespace bob HAS enabled answers true, so
    // the false above is about this namespace rather than a query that always
    // says no.
    expect(await CryptoRuntime(aliceClient).isReadyFor(bob, namespace), isTrue,
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
