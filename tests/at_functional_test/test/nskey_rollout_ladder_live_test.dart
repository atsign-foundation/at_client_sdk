// The nskey substrate and the enrollment key-package surface are
// @experimental; driving them is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The rollout-1 ladder within one atSign, against a live atServer.
///
/// Two installs of `@alice` share a namespace. One is on the rollout-1 build —
/// it mints both the old and the new algorithm and seals only to the old. The
/// other is on the previous build, which implements only the old. An atSign may
/// take rollout 1 one install at a time, in any order, with no window in which
/// the pair cannot talk.
///
/// ⚠️ **Two real enrollments, and nothing less.** The configured algorithm list
/// and the published advertisement are different things, and with one atSign
/// both belong to it — so a client consulting its own configuration where it
/// should consult the advertisement shows up nowhere else, and a fixture
/// serving both from one place would hide it here too.
///
/// ⚠️ **Both enrollments run `legacyPlusPqProviders` and the seeding is driven
/// by hand**, because of the mint lock: a seeding posture makes each client's
/// unawaited startup tail take `_nskeylock` at the production two-minute ttl,
/// and nothing releases a mint lock but expiry, so the second install's add is
/// refused for two minutes. The cost is that the wired tail is not what runs
/// here; what is proven is the behaviour of the mint, the add and the data
/// path, not their scheduling.
void main() {
  TestUtils.isolateStorage('nskey_rollout_ladder_live_test');
  late String atSign;
  late AtClient approver;

  // NOTE: unique per run, both halves. The namespace, because an already-seeded
  // one makes the mint below a no-op and every assertion holds for the absence
  // of work. The (appName, deviceName) pair, because the atServer refuses a
  // second enrollment carrying a pair that already has one approved.
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

  /// Each install's keyfile, kept because whether an install has FILED the
  /// private is one of the three states below, and the keyfile is where filing
  /// lands.
  final keyfiles = <String, InMemoryAtKeysIo>{};

  /// [mints] is what this install's build can mint and advertise; [sealsTo] is
  /// what it seals to as a sender, and rollout 1 is where the two differ.
  ///
  /// `signingAlgo: mldsa65` keeps the enrollment post-quantum from birth so the
  /// client does not retrofit itself on first construction, which would leave
  /// it running as a different enrollment from the one returned here.
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
        atKeysIo: keyfiles[device] = InMemoryAtKeysIo(),
        storage: TestUtils.storage,
      );

  /// Points [client] at the atSign's published generation for the data path,
  /// sealing only to [sealsTo].
  void useTheSharedGeneration(AtClient client, List<String> sealsTo) {
    client.getPreferences()!.crypto = CryptoConfig.nskey(
        keyRing: PublishedNskeyKeyRing(client), sealsToKeyAlgorithms: sealsTo);
  }

  test('rollout 1 goes one install at a time, and both directions keep working',
      () async {
    final old = await enrol('ladder-old',
        mints: const [SecretSharingAlgos.xWing],
        sealsTo: const [SecretSharingAlgos.xWing]);
    // Rollout 1 is exactly this pairing: the receive capability moves, the send
    // posture does not.
    final rolled = await enrol('ladder-new',
        mints: const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024],
        sealsTo: const [SecretSharingAlgos.xWing]);

    // NOTE: not ceremony. While `AtClientImpl` hands back a CACHED client for
    // an atSign, none of `enrolAndAuthenticate`'s arguments are applied and
    // both installs run as one, satisfying everything below while exercising a
    // single build twice.
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

    // NOTE: by hand, because this file runs `legacyPlusPqProviders` and so does
    // not get the wired startup tail the envelope listener lives in.
    // `_handleRequestPayload`, which answers another enrollment's request for a
    // secret, is reachable only from `sweepOnce`, so a holder that is not
    // listening never sees a request arriving after its own start and the
    // conveyance phases below cannot pass however long they wait.
    //
    // Only the rollout-1 install listens from here, because it must receive the
    // answers to its asks. The older install starts listening after state 1: a
    // listening holder answers in the first sweep that sees a request, and on a
    // slow runner that answer lands inside the very read state 1 expects to
    // miss.
    await AtClientSecretSharing.forClient(rolled.client).startListening();
    addTearDown(() {
      AtClientSecretSharing.forClient(old.client).stopListening();
      AtClientSecretSharing.forClient(rolled.client).stopListening();
    });

    final oldRing = PublishedNskeyKeyRing(old.client, lockTtl: shortLockTtl);
    final oldSeeding = NskeySeeding(
        atClient: old.client,
        ring: oldRing,
        privateFiling: oldRing.privateFiling);
    await oldSeeding.seedNamespace(atSign, namespace);
    final before = await oldRing.publishedAdvertisement(atSign, namespace);
    expect(before, isNotNull,
        reason: 'without a generation there is nothing '
            'for the rollout-1 install to add to');
    expect(before!.keys.map((k) => k.alg).toSet(), {SecretSharingAlgos.xWing},
        reason: 'the older build can fill exactly one slot, which is what '
            'leaves the generation short of what the newer one mints');
    final sharedKid = before.keys.single.kid;

    // NOTE: nothing releases a mint lock but expiry, so the add below is
    // refused inside the window.
    await waitOutTheLock();

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

    // NOTE: remote both ways. Two installs of one atSign are two devices with
    // two local stores and two keyfiles, so a record crosses between them
    // through the atServer; reading locally goes green without the seal being
    // exercised end to end.
    final remoteWrite = PutRequestOptions()..useRemoteAtServer = true;
    final remoteRead = GetRequestOptions()..useRemoteAtServer = true;

    // ── c1: the direction that needs no conveyance ──
    // `old` minted the shared generation, so it already holds the private.
    // Asserted first so a failure here reads as the seal being wrong rather
    // than the delivery.
    final fromRolled = AtKey()
      ..key = 'ladder_new_$runId'
      ..namespace = namespace
      ..sharedBy = atSign;
    await rolled.client.put(fromRolled, 'written by the rollout-1 install',
        putRequestOptions: remoteWrite);
    expect(
        (await old.client.get(fromRolled, getRequestOptions: remoteRead)).value,
        'written by the rollout-1 install',
        reason: 'c1: the rollout-1 install added an algorithm without changing '
            'what it seals to, so the older install opens it with the private '
            'it minted itself — no conveyance in this direction');

    // NOTE: a holder answers a request from its secret store, which the mint
    // does not fill — the bootstrap primes it from the filing at every start,
    // and this file drives that by hand. Priming here rather than at the mint
    // leaves the rollout-1 install's earlier asks unanswered, which is what an
    // ask to an unprimed holder gets: nothing back, and nothing logged.
    expect(
        await oldSeeding.hydrateStoreFromFiling(
            AtClientSecretSharing.forClient(old.client)),
        greaterThan(0),
        reason: 'the minted private must be in the older install\'s answer '
            'store, or no request for it is ever answered');

    // ── c2: the direction that DOES need conveyance, in its three states ──
    //
    // `rolled` never minted the shared generation, so it can only read what
    // `old` seals by having been conveyed the private. The three states are
    // walked in order because they are cumulative: a filed private cannot be
    // un-filed.
    final fromOld = AtKey()
      ..key = 'ladder_old_$runId'
      ..namespace = namespace
      ..sharedBy = atSign;
    await old.client.put(fromOld, 'written by the previous build',
        putRequestOptions: remoteWrite);

    final rolledKeys = keyfiles['ladder-new']!;
    final rolledFiling = NskeyPrivateFiling(keysIo: rolledKeys, atSign: atSign);
    final rolledSharing = AtClientSecretSharing.forClient(rolled.client);
    final secretName = '${NskeyPrivateFiling.secretNamePrefix}$sharedKid';

    Future<String?> readFromOld() async =>
        (await rolled.client.get(fromOld, getRequestOptions: remoteRead)).value;

    // ── state 1 of 3: NOT CONVEYED ──
    expect(await rolledFiling.read(namespace, sharedKid), isNull,
        reason: 'the precondition for this state: nothing has filed the '
            'private into this install\'s keyfile yet');
    expect(rolledSharing.secretStore.getSecret(namespace, secretName), isNull,
        reason: 'and nothing is waiting in the transit store either, so this '
            'really is the un-conveyed state rather than an unfiled one');

    await expectLater(readFromOld(), throwsA(isA<AtDecryptionException>()),
        reason: 'state 1: an install that has never been conveyed the private '
            'cannot open the record. The read does not block waiting for a '
            'holder to answer — `privateHalf` broadcasts an ask and returns '
            'the miss, so the caller sees it now and retries later');

    // The holder listens only from here: its start-up sweep answers the
    // requests its sync has pulled, and every ask so far is still in its store,
    // unswept and so unanswered.
    await AtClientSecretSharing.forClient(old.client).startListening();

    // ── state 2 of 3: CONVEYED, NOT FILED ──
    // The asks above are answered by `old`, which holds the private. The answer
    // lands in the transit store, and nothing files it mid-session.
    Secret? conveyed;
    try {
      conveyed = await rolledSharing.waitForSecret(namespace, secretName,
          timeout: const Duration(seconds: 60));
    } on TimeoutException {
      conveyed = null;
    }
    expect(conveyed, isNotNull,
        reason: 'state 2 precondition: the ask state 1 broadcast must have '
            'been answered by the install that minted the generation, or '
            'there is no conveyed-but-unfiled state to measure');

    // NOTE: the read below may succeed — `waitForSecret` above consumed the
    // arrival, and `requestAndFileNskeyPrivate`, the same ask state 1 fired,
    // files what it waits for. State 2 pins that material being ON the device
    // is not by itself enough for `privateHalf`, which looks only in memory and
    // in the keyfile.
    expect(
        rolledSharing.secretStore.getSecret(namespace, secretName), isNotNull,
        reason: 'state 2: the conveyed private is on this device, in the '
            'transit store, whether or not anything has filed it');

    // ── state 3 of 3: CONVEYED AND FILED ──
    await rolledFiling.file(conveyed!);
    expect(await rolledFiling.read(namespace, sharedKid), isNotNull,
        reason: 'state 3 precondition: the private is now in the keyfile, '
            'which is where `privateHalf` looks after memory');

    expect(await readFromOld(), 'written by the previous build',
        reason: 'state 3: with the private filed, the older install\'s seal '
            'opens immediately — no ask, no wait. c2 of UC-G2.11: the older '
            'build seals to the entry it always used and the rollout-1 build '
            'holds it');
  }, timeout: Timeout(Duration(minutes: 5)));
}
