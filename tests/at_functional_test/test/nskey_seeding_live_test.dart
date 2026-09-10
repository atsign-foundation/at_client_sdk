// The nskey surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Namespace-key seeding against a live atServer.
///
/// Asserts the outcome on the atServer rather than that a method was called:
/// after seeding, the advertisement is fetchable by the exact lookup a sender
/// would use, and the client holds the matching private.
void main() {
  TestUtils.isolateStorage('nskey_seeding_live_test');
  late String atSign;
  // NOTE: a namespace nothing has minted for, so the first seed provably does
  // work. Against a shared one the seed would adopt an existing key and every
  // assertion below would hold for the absence of seeding.
  final namespace = 'seed${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('seeding publishes an advertisement the owner can then resolve',
      () async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: PqPosture.legacy);
    final atClient = manager.atClient;

    final ring = PublishedNskeyKeyRing(atClient);
    final seeding = NskeySeeding(atClient: atClient, ring: ring);

    final authorised = await seeding.authorisedNamespaces();
    expect(authorised, contains(namespace),
        reason: 'seeding mints for the namespaces this client is authorised '
            'for; with none, there is nothing to observe');

    expect(await ring.currentPublic(atSign, namespace), isNull,
        reason: 'the precondition: nothing has minted for this namespace, so '
            'the seed below has real work to do');

    expect(await seeding.seed(), contains(namespace),
        reason: 'seed() must report that it minted THIS namespace. Without '
            'this the test would pass just as well against a namespace that '
            'was already seeded, which is the failure mode it exists to rule '
            'out');

    // NOTE: an exact lookup is the only way a published nskey is reachable; it
    // is absent from every scan.
    final resolved =
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, namespace);
    expect(resolved, isNotNull,
        reason: 'after seeding, the namespace must have a published '
            'advertisement — without one no sender can seal to this atSign, '
            'and the client would report cold start forever');
    expect(resolved!.publicKey, isNotEmpty);

    final private =
        await ring.privateHalf(atSign, namespace, resolved.nskeyKid);
    expect(private, isNotNull,
        reason: 'the client must hold the private for the generation it just '
            'advertised, or it has invited traffic it cannot read');

    // Idempotent: a second start must adopt the existing advertisement, since
    // rotating here would strand every peer holding the old generation.
    final again = NskeySeeding(atClient: atClient, ring: ring);
    final minted = await again.seed();
    expect(minted, isEmpty,
        reason: 'seeding is run at every start; if it re-minted each time, an '
            'atSign would rotate its namespace keys on every launch and no '
            'sender could keep up');
    expect(
        (await PublishedNskeyKeyRing(atClient).currentPublic(atSign, namespace))
            ?.nskeyKid,
        resolved.nskeyKid,
        reason: 'and the advertisement is the same generation as before');
  });
}
