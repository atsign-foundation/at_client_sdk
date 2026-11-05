@Tags(['pq'])
library;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// `PublishedNskeyKeyRing` against a live atServer, same-atSign.
///
/// A client that has minted nothing — another enrollment, or this one after a
/// restart — must find the advertisement its atSign already published, and the
/// owner verifies it by the same path a peer would. Reporting a published
/// namespace as cold start and minting again would rotate the key out from
/// under every peer that had already fetched it.
void main() {
  TestUtils.isolateStorage('nskey_published_ring_test');
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
    final fresh =
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, ns);

    expect(fresh?.nskeyKid, minted.nskeyKid,
        reason: 'the advertisement is on the atServer; a client holding no '
            'memory of it must fetch it rather than report cold start');
    expect(fresh?.publicKey, minted.publicKey);
  });

  test('the owner verifies her own advertisement the same way a peer would',
      () async {
    final ns = uniqueNs();
    await PublishedNskeyKeyRing(atClient).mintAndPublish(ns);

    final substitute = await XWingKeyPair.generate();
    final unsigned = '{"v":1,"keys":[{"kid":'
        '"${nskeyKidOf(substitute.publicKeyBytes)}","use":"enc",'
        '"alg":"x-wing","pub":"unsigned"}]}';
    // NOTE: local-first, deliberately. `currentPublic` reads through
    // `atClient.get`, so substituting only on the atServer would leave the
    // genuine local copy answering and the test would prove nothing.
    await atClient.put(nskeyAdvertisementKey(atSign, ns), unsigned);

    await expectLater(
      PublishedNskeyKeyRing(atClient).currentPublic(atSign, ns),
      throwsA(isA<AtSigningVerificationException>()),
      reason: 'an unsigned advertisement is refused whoever published it — the '
          'owner is not a special case',
    );
  });

  test('a rotation publishes a new generation and keeps the old private',
      // It waits out a whole liveMintLockTtl.
      timeout: const Timeout(Duration(minutes: 1)), () async {
    final ns = uniqueNs();
    // NOTE: the cold-start mint below holds the lock, and the rotation that
    // follows is refused until it lapses.
    final ring = PublishedNskeyKeyRing(atClient, lockTtl: liveMintLockTtl, lockBudgetPerMember: Duration.zero);
    // NOTE: the second generation comes from the rotation lever, not a second
    // mint — a mint that loses the lock adopts the winner and reports success,
    // so it cannot fail the way rotation fails.
    final first = await ring.mintAndPublish(ns);
    await waitOutMintLock(atClient, ns);
    final second = (await ring.rotate(ns)).rotated;

    expect(second.nskeyKid, isNot(first.nskeyKid),
        reason: 'a rotation is a new generation, not an edit of the old one');

    // NOTE: read the atServer's copy. A fresh ring's `currentPublic` still
    // reads local-first for its own atSign, and a sync pull can regress that
    // copy to the superseded generation moments after the rotation.
    expect(
        (await PublishedNskeyKeyRing(atClient)
                .publishedAdvertisement(atSign, ns))
            ?.nskeyKid,
        second.nskeyKid);

    expect(await ring.privateHalf(atSign, ns, first.nskeyKid), isNotNull,
        reason: 'rotation must not retire data written under the old key');
    expect(await ring.privateHalf(atSign, ns, second.nskeyKid), isNotNull);
  });

  test(
      'a cold-start mint whose filing takes 8 s still publishes inside the '
      'live mint lock',
      timeout: const Timeout(Duration(minutes: 1)), () async {
    final ns = uniqueNs();
    const slowFiling = Duration(seconds: 8);
    final ring = PublishedNskeyKeyRing(atClient,
        lockTtl: liveMintLockTtl,
        lockBudgetPerMember: liveMintLockBudgetPerMember);
    // NOTE: the hold runs inside the mint lock, after the lock is taken and
    // before the advertisement is published.
    ring.privateFiling!.holdBeforeStore =
        () => Future<void>.delayed(slowFiling);

    final minting = Stopwatch()..start();
    final minted = await ring.mintAndPublish(ns);
    minting.stop();

    expect(minting.elapsed, greaterThanOrEqualTo(slowFiling),
        reason: 'the control: the filing was held inside the mint, so the '
            'publish below happened after the hold and not before it');
    expect(
        (await PublishedNskeyKeyRing(atClient)
                .publishedAdvertisement(atSign, ns))
            ?.nskeyKid,
        minted.nskeyKid,
        reason: 'the generation minted is the one the atServer publishes');
  });

  test('a namespace nobody minted for resolves to nothing', () async {
    expect(
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, uniqueNs()),
        isNull,
        reason: 'and that is cold start, which the provider turns into a named '
            'refusal');
  });
}
