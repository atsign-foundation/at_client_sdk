@Tags(['pq'])
library;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// `PublishedNskeyKeyRing` against a live atServer, same-atSign.
///
/// The rest of the nskey coverage seeds an `InMemoryNskeyKeyRing`, so nothing
/// drives the real publish-and-discover path within one atSign. That left two
/// things unproven:
///
/// - A client that has minted **nothing** — another enrollment, or this one
///   after a restart — has to find the advertisement its atSign already
///   published. Reporting that as cold start would be wrong twice: the namespace
///   is published, and "fixing" it by minting would rotate the key out from
///   under every peer that had already fetched it.
/// - The design claims **one** verify path, same-atSign and cross-atSign. The
///   cross-atSign half is covered in `at_end2end_test`; this is the other half,
///   and until it ran the claim was aspirational.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
    atClient = manager.atClient;
  });

  String uniqueNs() => 'ns${DateTime.now().microsecondsSinceEpoch}.$namespace';

  test('a client that minted nothing resolves the published advertisement',
      () async {
    final ns = uniqueNs();
    final minted = await PublishedNskeyKeyRing(atClient).mintAndPublish(ns);

    // A second ring over the same client: no in-memory state, exactly like a
    // fresh enrollment or a restart.
    final fresh = await PublishedNskeyKeyRing(atClient).currentPublic(atSign, ns);

    expect(fresh?.nskeyKid, minted.nskeyKid,
        reason: 'the advertisement is on the atServer; a client holding no '
            'memory of it must fetch it rather than report cold start');
    expect(fresh?.publicKey, minted.publicKey);
  });

  test('the owner verifies her own advertisement the same way a peer would',
      () async {
    // Substitute an unsigned advertisement at the owner's own address. If the
    // same-atSign path skipped verification this would be accepted, and the
    // design's single-verify-path claim would be false.
    final ns = uniqueNs();
    await PublishedNskeyKeyRing(atClient).mintAndPublish(ns);

    final substitute = await XWingKeyPair.generate();
    final unsigned = '{"v":1,"keys":[{"kid":'
        '"${nskeyKidOf(substitute.publicKeyBytes)}","use":"enc",'
        '"alg":"x-wing","pub":"unsigned"}]}';
    // Local-first, deliberately: `currentPublic` reads through `atClient.get`,
    // so substituting only on the atServer would leave the genuine local copy
    // answering and the test would pass without proving anything.
    await atClient.put(nskeyAdvertisementKey(atSign, ns), unsigned);

    await expectLater(
      PublishedNskeyKeyRing(atClient).currentPublic(atSign, ns),
      throwsA(isA<AtSigningVerificationException>()),
      reason: 'an unsigned advertisement is refused whoever published it — the '
          'owner is not a special case',
    );
  });

  test('a rotation publishes a new generation and keeps the old private',
      () async {
    final ns = uniqueNs();
    // A short cooldown, because nothing releases a mint lock but its ttl: the
    // cold-start mint below holds it, and the rotation that follows is refused
    // until it lapses. At the production `mintLockTtl` this test would sit for
    // two minutes. The refusal itself is asserted in nskey_rotation_live_test.
    const lockTtl = Duration(seconds: 5);
    final ring = PublishedNskeyKeyRing(atClient, lockTtl: lockTtl);
    // Seed with the cold-start mint, then rotate with the rotation lever —
    // the sequence production runs. Minting twice also reaches a second
    // generation, but it is not what rotation does: on a lost mint lock it
    // adopts the winner and reports success, so a test driving it that way
    // asserts rotation's contract against a method that cannot fail the way
    // rotation fails.
    final first = await ring.mintAndPublish(ns);
    // A second past the ttl: the atServer starts counting when it stores the
    // record, after this client sent it.
    await Future.delayed(lockTtl + const Duration(seconds: 1));
    final second = (await ring.rotate(ns)).rotated;

    expect(second.nskeyKid, isNot(first.nskeyKid),
        reason: 'a rotation is a new generation, not an edit of the old one');

    // The advertisement is mutable by design, so the atServer now serves only
    // the new generation — that is what a sender re-plookups and picks up.
    // Read the atServer's copy: a fresh ring's `currentPublic` still reads
    // local-first for its own atSign, and a sync pull can regress that copy
    // to the superseded generation moments after the rotation.
    expect(
        (await PublishedNskeyKeyRing(atClient)
                .publishedAdvertisement(atSign, ns))
            ?.nskeyKid,
        second.nskeyKid);

    // But the ring keeps the superseded private, or every conveyance sealed to
    // it before the rotation would become unreadable.
    expect(await ring.privateHalf(atSign, ns, first.nskeyKid), isNotNull,
        reason: 'rotation must not retire data written under the old key');
    expect(await ring.privateHalf(atSign, ns, second.nskeyKid), isNotNull);
  });

  test('a namespace nobody minted for resolves to nothing', () async {
    expect(
        await PublishedNskeyKeyRing(atClient)
            .currentPublic(atSign, uniqueNs()),
        isNull,
        reason: 'and that is cold start, which the provider turns into a named '
            'refusal');
  });
}
