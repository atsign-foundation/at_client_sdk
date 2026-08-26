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
/// Seeding had unit coverage only, and the unit tests cannot see the thing
/// most likely to be wrong: whether the path runs at all. `AtClientImpl._init`
/// calls it behind `AtClientPreference.seedNamespaceKeys` and does not await
/// it, so a client whose seeding silently never fired would pass every unit
/// assertion — the same shape of gap that has bitten this branch twice, where
/// a code path looked wired, was unit-green, and never executed.
///
/// What is asserted is the *outcome on the atServer*, not that a method was
/// called: after seeding, the advertisement is fetchable by the exact lookup a
/// sender would use, and the client holds the matching private. A mint that
/// published nothing, or published something whose private was lost, is
/// indistinguishable from a mint that never happened until you look there.
void main() {
  late String atSign;
  // A namespace nothing has minted for, so the first seed below provably does
  // work. Against the shared `wavi` the first seed would find an existing key,
  // return empty, and every assertion here would hold for the absence of
  // seeding rather than for seeding.
  final namespace = 'seed${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('seeding publishes an advertisement the owner can then resolve',
      () async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo,
            posture: PqPosture.legacy);
    final atClient = manager.atClient;

    final ring = PublishedNskeyKeyRing(atClient);
    final seeding = NskeySeeding(atClient: atClient, ring: ring);

    // A legacy PKAM client has no enrollment record, so it can name exactly
    // one namespace — its preference namespace. Checked rather than assumed:
    // if this came back empty, seed() would be a no-op and everything below
    // would pass for the absence of work rather than for the work.
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

    // The sender's view: an exact lookup, which is the only way a published
    // nskey is reachable — it is deliberately absent from every scan.
    final resolved =
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, namespace);
    expect(resolved, isNotNull,
        reason: 'after seeding, the namespace must have a published '
            'advertisement — without one no sender can seal to this atSign, '
            'and the client would report cold start forever');
    expect(resolved!.publicKey, isNotEmpty);

    // And the half that makes it usable rather than merely present. A
    // published public whose private was never filed is worse than no key at
    // all: the record is advertised, senders seal to it, and nothing can open
    // what comes back.
    final private =
        await ring.privateHalf(atSign, namespace, resolved.nskeyKid);
    expect(private, isNotNull,
        reason: 'the client must hold the private for the generation it just '
            'advertised, or it has invited traffic it cannot read');

    // Idempotent: a second start must adopt the existing advertisement rather
    // than mint over it. Rotating here would strand every peer that had
    // already fetched the old generation.
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
