// The nskey substrate and the enrollment key-package surface are
// @experimental; driving them is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The rollout-1 ladder **within one atSign**, against a live atServer.
///
/// Two installs of `@alice` share a namespace. One is on the rollout-1 build —
/// it mints both the old and the new algorithm and seals only to the **old**.
/// The other is still on the previous build, which implements only the old.
/// The claim is that an atSign may take rollout 1 one install at a time, in any
/// order, with no window in which the pair cannot talk.
///
/// ⚠️ **Two enrollments and nothing less, and a mock cannot stand in.** The
/// catalogue says why: *the configured list and the published advertisement are
/// different things, and this is the row where confusing them shows*. With one
/// atSign both belong to it, so a client consulting its own configuration where
/// it should consult the advertisement is invisible in every other row — and a
/// fixture serving both from one place would hide it here too.
///
/// ⚠️ **Both enrollments run `legacyPlusPqProviders` and the seeding is driven by
/// hand.** Not because the posture is the subject, but because of the mint
/// lock: a seeding posture makes each client's unawaited startup tail take
/// `_nskeylock` at the production two-minute ttl, and nothing releases a mint
/// lock but expiry — so the second install's add is refused for two minutes,
/// which is the interlock working rather than a defect. The same reason
/// `nskey_rotation_live_test.dart` injects a short ttl. The cost is that the
/// wired tail is not what runs here; what is proven is the behaviour of the
/// mint, the add and the data path, not their scheduling.
void main() {
  late String atSign;
  late AtClient approver;

  // Unique per run, both halves. The namespace, because an already-seeded one
  // would make the mint below a no-op and every assertion would hold for the
  // absence of work. The (appName, deviceName) pair, because the atServer
  // refuses a second enrollment carrying a pair that already has one approved.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'ladder$runId';

  /// Short enough to wait out, long enough that no mint here races its own
  /// expiry — a keygen, a keyfile write, a signature and two round trips.
  const shortLockTtl = Duration(seconds: 5);

  Future<void> waitOutTheLock() =>
      Future.delayed(shortLockTtl + const Duration(seconds: 1));

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  /// [mints] is what this install's build can mint and advertise;
  /// [sealsTo] is what it will seal to as a sender. They are different axes
  /// and rollout 1 is precisely the release where they differ.
  ///
  /// `signingAlgo: mldsa65` so the enrollment is post-quantum from birth and
  /// the client does not retrofit itself on first construction — a retrofit
  /// would leave this client running as a different enrollment from the one
  /// returned here, which is real behaviour and not what this row is about.
  Future<EnrolledClient> enrol(String device,
          {required List<String> mints, required List<String> sealsTo}) =>
      enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign,
            posture: legacyPlusPqProviders,
            keyEstablishmentAlgorithms: mints,
            sealsToKeyAlgorithms: sealsTo),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        signingAlgo: SigningAlgoType.mldsa65,
        deviceName: '$device-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw', namespace: 'rw'},
        atKeysIo: InMemoryAtKeysIo(),
      );

  /// Points [client] at the atSign's published generation for the data path,
  /// sealing only to [sealsTo].
  void useTheSharedGeneration(AtClient client, List<String> sealsTo) {
    client.getPreferences()!.crypto = CryptoConfig.nskey(
        keyRing: PublishedNskeyKeyRing(client), sealsToKeyAlgorithms: sealsTo);
  }

  test('rollout 1 goes one install at a time, and both directions keep working',
      () async {
    // The previous build: it implements only the old algorithm.
    final old = await enrol('ladder-old',
        mints: const [SecretSharingAlgos.xWing],
        sealsTo: const [SecretSharingAlgos.xWing]);
    // The rollout-1 build: mints BOTH, seals only to the OLD. That pairing is
    // the whole of rollout 1 — the receive capability moves, the send posture
    // does not.
    final rolled = await enrol('ladder-new',
        mints: const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024],
        sealsTo: const [SecretSharingAlgos.xWing]);

    // ⛔ Not ceremony. `enrolAndAuthenticate` warns that while AtClientImpl
    // hands back a CACHED client for an atSign none of its arguments are
    // applied, and this row would then run both installs as one — satisfying
    // everything below while measuring a single build twice.
    expect(rolled.enrollmentId, isNot(old.enrollmentId));
    expect(identical(rolled.client, old.client), isFalse);
    expect(old.client.getPreferences()?.keyEstablishmentAlgorithms,
        const [SecretSharingAlgos.xWing],
        reason: 'the older install must really be the older build, or the add '
            'below has nothing to add and this row passes for that');
    expect(rolled.client.getPreferences()?.keyEstablishmentAlgorithms,
        const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

    await AtClientSecretSharing.forClient(old.client).register();
    await AtClientSecretSharing.forClient(rolled.client).register();

    // The older install seeds what its build can mint.
    final oldRing = PublishedNskeyKeyRing(old.client, lockTtl: shortLockTtl);
    await NskeySeeding(atClient: old.client, ring: oldRing)
        .seedNamespace(atSign, namespace);
    final before = await oldRing.publishedAdvertisement(atSign, namespace);
    expect(before, isNotNull,
        reason: 'without a generation there is nothing '
            'for the rollout-1 install to add to');
    expect(before!.keys.map((k) => k.alg).toSet(), {SecretSharingAlgos.xWing},
        reason: 'the older build can fill exactly one slot, which is what '
            'leaves the generation short of what the newer one mints');
    final sharedKid = before.keys.single.kid;

    // The winner holds the lock for its full ttl; nothing releases it but
    // expiry, so the add would be refused inside the window.
    await waitOutTheLock();

    // Rollout 1 on the second install: it adds the new algorithm.
    await NskeySeeding(
            atClient: rolled.client,
            ring: PublishedNskeyKeyRing(rolled.client, lockTtl: shortLockTtl))
        .seedNamespace(atSign, namespace);

    final after = await PublishedNskeyKeyRing(approver)
        .publishedAdvertisement(atSign, namespace);
    expect(after!.keys.map((k) => k.alg).toSet(),
        {SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024},
        reason: 'rollout 1 puts the new algorithm into the SHARED generation');
    expect(after.keys.map((k) => k.kid), contains(sharedKid),
        reason: 'and leaves what was already there untouched — the older '
            'install goes on finding the entry it minted');
    expect(after.createdAt, before.createdAt,
        reason: 'an add joins the current generation; refreshing createdAt '
            'would make a pre-revocation generation read as post-revocation');

    // ── UC-G2.11 c1 and c2: both directions still succeed ──
    useTheSharedGeneration(old.client, const [SecretSharingAlgos.xWing]);
    useTheSharedGeneration(rolled.client, const [SecretSharingAlgos.xWing]);

    final fromRolled = AtKey()
      ..key = 'ladder_new_$runId'
      ..namespace = namespace
      ..sharedBy = atSign;
    await rolled.client.put(fromRolled, 'written by the rollout-1 install');
    expect((await old.client.get(fromRolled)).value,
        'written by the rollout-1 install',
        reason: 'c1: the rollout-1 install added an algorithm without '
            'changing what it seals to, so the older install finds what it '
            'has always found');

    final fromOld = AtKey()
      ..key = 'ladder_old_$runId'
      ..namespace = namespace
      ..sharedBy = atSign;
    await old.client.put(fromOld, 'written by the previous build');
    expect((await rolled.client.get(fromOld)).value,
        'written by the previous build',
        reason: 'c1, the other direction: the older install seals to the '
            'entry it always used, and the rollout-1 install still holds it');
  }, timeout: Timeout(Duration(minutes: 5)));
}
