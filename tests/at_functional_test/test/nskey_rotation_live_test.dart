// The substrate, the nskey surface and the rotation levers are @experimental;
// driving them is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show ckConveyanceKey;
import 'package:at_client/src/crypto/nskey/nskey_rotation.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The two rotation levers, driven against a live atServer, and the revocation
/// they compose with.
///
/// Neither substitutes for the other: rotating the nskey **keypair** denies an
/// enrollment the keys that protect data written from now on and leaves every
/// earlier content key readable, while rotating the **content key** and
/// deleting its conveyance is what makes already-written data unreadable.
void main() {
  TestUtils.isolateStorage('nskey_rotation_live_test');
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    // NOTE: the SECOND atSign, not the first. These tests create enrollments
    // and REVOKE one, and both are shared state the rest of the suite reads:
    // every enroll:listns walks the whole roster, and a revoked enrollment's
    // _apsk is deleted for good.
    atSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  // NOTE: unique per run — the atServer refuses a second enrollment carrying
  // an (appName, deviceName) pair that already has one approved, so fixed
  // names collide on the second run against the same virtualenv.
  final runId = DateTime.now().microsecondsSinceEpoch;

  /// The mint lock's ttl for these tests, and it is not a speed-up.
  ///
  /// Nothing releases a mint lock but expiry, so the ttl is a **cooldown**:
  /// after a cold-start mint takes the lock, a rotation of the same namespace
  /// is refused until it lapses — long enough that no mint here races its own
  /// expiry, short enough to wait out.
  ///
  /// The floor is the winner's own budget: a holder carries the matching
  /// `MintLease` and abandons rather than publishing once the ttl has elapsed,
  /// so this must outlast a mint. A mint or rotation against a local
  /// virtualenv measured at most 35ms, which this leaves ample room over.
  const shortLockTtl = Duration(seconds: 1);

  /// Waits until the lock a mint just took has expired.
  ///
  /// Past the ttl rather than exactly it, because the atServer starts counting
  /// when it stores the record — after this client sent it — so waiting the
  /// ttl alone can land a moment early. That gap measured at most ~100ms
  /// against a local virtualenv.
  Future<void> pastTheCooldown() =>
      Future.delayed(shortLockTtl + const Duration(milliseconds: 500));

  Future<EnrolledClient> enrol(String device,
          {AtKeysIo? atKeysIo, Map<String, String>? namespaces}) =>
      enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference:
            TestUtils.getPreference(atSign, posture: legacyPlusPqProviders),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        atKeysIo: atKeysIo,
        namespaces: namespaces,
        storage: TestUtils.storage,
      );

  /// What revocation needs, which is not what rotation needs: revoking is gated
  /// on `__manage`, and a client without it cannot even enumerate the atSign's
  /// enrollments to find the one it means.
  const operatorGrants = {'*': 'rw', '__manage': 'rw', namespace: 'rw'};

  /// An enrollment with its own keyfile, sharing substrate, filing and ring —
  /// everything a client needs to hold and answer for a namespace key.
  Future<
      ({
        EnrolledClient enrolled,
        InMemoryAtKeysIo io,
        AtClientSecretSharing sharing,
        NskeyPrivateFiling filing,
        PublishedNskeyKeyRing ring,
      })> holder(String device, {Map<String, String>? namespaces}) async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final enrolled = await enrol(device, atKeysIo: io, namespaces: namespaces);
    final sharing = AtClientSecretSharing.forClient(enrolled.client);
    await sharing.register();
    final filing = NskeyPrivateFiling(keysIo: io, atSign: atSign);
    return (
      enrolled: enrolled,
      io: io,
      sharing: sharing,
      filing: filing,
      ring: PublishedNskeyKeyRing(enrolled.client,
          privateFiling: filing, lockTtl: shortLockTtl),
    );
  }

  /// Writes [name] on the nskey data path and answers which nskey generation
  /// the content key's conveyance was sealed to.
  ///
  /// Reads the conveyance LOCALLY, through `getMeta`, which does not decrypt: a
  /// self conveyance is written local-first, so asking the atServer races the
  /// push and fails with "does not exist in keystore".
  Future<String?> sealedGeneration(AtClient client, String name) async {
    final key = AtKey()
      ..key = name
      ..namespace = namespace
      ..sharedBy = atSign
      ..sharedWith = atSign;
    expect(await client.put(key, 'sealed under whichever generation is live'),
        true);

    final written = await client.get(key);
    expect(written.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: '$name must be on the nskey data path, or it has no content '
            'key and no conveyance and there is no generation to read off it');
    final ckKid =
        written.metadata?.appMetadata?.additional?['ckKid'] as String?;
    expect(ckKid, isNotNull);

    final conveyance = ckConveyanceKey(key, ckKid!, namespace);
    final meta = await client.getMeta(conveyance);
    expect(meta, isNotNull,
        reason: 'the content key for $name must have a conveyance at '
            '${conveyance.toString()}');
    final sealedTo = meta!.appMetadata?.additional?['nskeyKid'] as String?;
    expect(sealedTo, isNotNull,
        reason: 'the conveyance must name the generation it was sealed to, or '
            'no reader can tell which private opens it');
    return sealedTo;
  }

  test(
      'UC-A5.1(b) · a rotation publishes a successor, pushes it to the '
      'survivor, and leaves the excluded enrollment on the old generation',
      () async {
    final rotator = await holder('rot-rotator');
    final survivor = await holder('rot-survivor');
    final excluded = await holder('rot-excluded');
    expect({
      rotator.enrolled.enrollmentId,
      survivor.enrolled.enrollmentId,
      excluded.enrolled.enrollmentId
    }, hasLength(3),
        reason: 'three distinct enrollments, or the exclusion '
            'below is excluding the pusher from itself');

    final first = await rotator.ring.mintAndPublish(namespace);
    final firstPrivate = await rotator.filing.read(namespace, first.nskeyKid);
    expect(firstPrivate, isNotNull);

    // NOTE: the ring installed is the rotator's OWN — a bare
    // `PublishedNskeyKeyRing(client)` built over the top would take the filing
    // and the read path's self-heal away with it.
    rotator.enrolled.client.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: rotator.ring);
    final beforeSealedTo =
        await sealedGeneration(rotator.enrolled.client, 'before$runId');
    expect(beforeSealedTo, first.nskeyKid,
        reason: 'the baseline: before the rotation, a write seals its content '
            'key to the generation published at the time. Without this the '
            'assertion after the rotation cannot tell a writer that MOVED '
            'from one that was always going to name that kid');

    final rotation = NskeyRotation(
      atClient: rotator.enrolled.client,
      ring: rotator.ring,
      privateFiling: rotator.filing,
      sharing: rotator.sharing,
    );

    await pastTheCooldown();

    final outcome = await rotation.rotateNamespaceKey(namespace,
        excludeEnrollmentIds: {excluded.enrolled.enrollmentId});

    expect(outcome.supersededKid, first.nskeyKid);
    expect(outcome.advertisement.nskeyKid, isNot(first.nskeyKid));
    expect(outcome.conveyedTo, greaterThan(0),
        reason: 'the survivor has a key package registered for this '
            'namespace, so the push must find somebody');

    // NOTE: `publishedAdvertisement`, which reads the atServer directly and
    // verifies the signature on the way — `currentPublic` serves this ring's
    // caches and then a LOCAL-first get, which an in-flight sync pull can
    // regress to the superseded generation moments after a rotation.
    final published =
        await survivor.ring.publishedAdvertisement(atSign, namespace);
    expect(published?.nskeyKid, outcome.advertisement.nskeyKid,
        reason: 'the advertisement is OVERWRITTEN — that is what makes new '
            'content keys seal to the successor, and it is the only signal a '
            'peer ever gets that a rotation happened');

    await survivor.sharing.sweepOnce(fromRemote: true);
    var filed =
        await survivor.filing.read(namespace, outcome.advertisement.nskeyKid);
    for (var i = 0; i < 20 && filed == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await NskeyPrivateFiling(keysIo: survivor.io, atSign: atSign)
          .filePending(survivor.sharing.secretStore.listSecrets());
      filed =
          await survivor.filing.read(namespace, outcome.advertisement.nskeyKid);
    }
    expect(filed, isNotNull,
        reason: 'a rotation that publishes a generation nobody but the '
            'rotator can open takes the namespace away from its own atSign');

    // The exclusion, asserted where it bites: `excludeEnrollmentIds` reaches
    // `enroll:listns` and drops the member before an envelope is sealed to it.
    final directory = VerbEnrollmentDirectory(rotator.enrolled.client);
    expect(
        (await directory.listForNamespace(namespace))
            .map((m) => m.enrollmentId),
        contains(excluded.enrolled.enrollmentId),
        reason: 'the control arm: unexcluded, this enrollment IS a push '
            'target, so its absence below is the exclusion and not an '
            'enrollment that was never in the namespace');
    expect(
        (await directory.listForNamespace(namespace,
                excludeEnrollmentIds: {excluded.enrolled.enrollmentId}))
            .map((m) => m.enrollmentId),
        isNot(contains(excluded.enrolled.enrollmentId)));

    // NOTE: what the exclusion does NOT do is stop the excluded enrollment
    // pulling. A still-approved enrollment remains a member of the namespace,
    // so it can ask any holder for the generation it can see published and be
    // answered; only revocation removes it from every roster and every serve
    // (UC-A5.3 below). Nothing is asserted about that pull here, because
    // whether it completes inside a test depends on when a background
    // self-heal fires; the serve itself is pinned by the pull-flow group in
    // pairwise_secret_sharing_test.dart.

    // Rotation replaces the key; it does not decrypt or re-encrypt the past,
    // so conveyances sealed to the superseded generation still open.
    expect(await rotator.filing.read(namespace, first.nskeyKid), firstPrivate);
    expect(await rotator.ring.privateHalf(atSign, namespace, first.nskeyKid),
        isNotNull);

    final afterSealedTo =
        await sealedGeneration(rotator.enrolled.client, 'after$runId');
    expect(afterSealedTo, outcome.advertisement.nskeyKid,
        reason: 'a content key cut after the rotation is sealed to the '
            'SUCCESSOR, and its conveyance says which generation that is');
    expect(afterSealedTo, isNot(beforeSealedTo),
        reason: 'and the writer MOVED. Same client, same ring, same namespace '
            '— the rotation is the only thing that changed between the two '
            'writes, and a writer still sealing to the superseded generation '
            'would hand the excluded enrollment every new content key, so the '
            'revocation would have bought nothing');
  });

  test('a rotation inside the mint lock\'s cooldown is refused', () async {
    // NOTE: this cannot be a unit test — the interlock IS the atServer
    // refusing a second create of an immutable record, and a mocked
    // executeVerb accepts the second take happily.
    final ns = 'cooldown$runId.$namespace';
    final owner = await holder('cooldown-owner');

    final minted = await owner.ring.mintAndPublish(ns);

    await expectLater(
        owner.ring.rotate(ns),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'names the cooldown',
                contains('holds the mint lock'))
            // Nothing releases a mint lock but its ttl, so an error that does
            // not say to wait sends an operator looking for a stuck lock to
            // clear, and there is none to find.
            .having((e) => e.message, 'says the retry waits the ttl out',
                contains('retry once its ttl elapses'))),
        reason: 'the ttl is the only release, so an election held moments ago '
            'is still in its cooldown. A rotation must fail here rather than '
            'adopt: adopting would have rotated nothing while reporting '
            'success, leaving the enrollment being rotated away from on the '
            'live generation');

    // The control: the same call is accepted once the cooldown has lapsed, so
    // the refusal above is the lock and not an enrollment that cannot rotate.
    await pastTheCooldown();
    final rotated = (await owner.ring.rotate(ns)).rotated;
    expect(rotated.nskeyKid, isNot(minted.nskeyKid));
  });

  test(
      'UC-A5.2/A5.3 · a revoked enrollment cannot authenticate, and drops out '
      'of the roster every holder serves from',
      // Three full enrollments over the wire, plus a revoke and the roster
      // reads: the default is not a budget for that, and a bare
      // TimeoutException reads as the mechanism under test breaking.
      timeout: const Timeout(Duration(seconds: 90)), () async {
    final operator = await holder('rev-operator', namespaces: operatorGrants);
    final keeper = await holder('rev-keeper');
    final doomed = await holder('rev-doomed');

    expect({
      operator.enrolled.enrollmentId,
      keeper.enrolled.enrollmentId,
      doomed.enrolled.enrollmentId
    }, hasLength(3),
        reason: 'three distinct enrollments, or the credential this revokes '
            'is the same one it then expects to keep working');

    // NOTE: distinct ids do NOT imply distinct keypairs. A keyfile carries one
    // flat apkamPublicKey/apkamPrivateKey slot, so two enrollments sharing an
    // AtKeysIo would both read whichever wrote last, and the credential arm
    // below would present a live enrollment's key under a revoked id.
    expect({
      operator.enrolled.keys.apkamPublicKey!.toString(),
      keeper.enrolled.keys.apkamPublicKey!.toString(),
      doomed.enrolled.keys.apkamPublicKey!.toString(),
    }, hasLength(3),
        reason: 'three enrollments sharing one APKAM keypair makes the '
            'credential arm below meaningless — whichever key it presents '
            'would belong to an enrollment nobody revoked');

    /// The APKAM public key the atServer holds for [enrollmentId], read off the
    /// roster rather than inferred from this process's own state.
    Future<String?> servedApkamKeyFor(String enrollmentId) async {
      final response = await operator.enrolled.client
          .getRemoteSecondary()!
          .executeCommand('enroll:listns:$namespace\n', auth: true);
      final roster =
          jsonDecode(response!.replaceFirst('data:', '').trim()) as List;
      final mine = roster
          .cast<Map<String, dynamic>>()
          .where((e) => e['enrollmentId'] == enrollmentId)
          .firstOrNull;
      return mine?['apkamPubKey'] as String?;
    }

    expect(await servedApkamKeyFor(doomed.enrolled.enrollmentId),
        doomed.enrolled.keys.apkamPublicKey!.toString(),
        reason: 'the keypair this test is about to present must be the one '
            'the atServer holds for the doomed enrollment, or the refusal it '
            'expects afterwards would be a signature mismatch wearing the '
            'revoke\'s clothes');

    /// What a fresh connection presenting [enrolled]'s own APKAM keypair gets
    /// back — the atServer's answer, not a boolean.
    ///
    /// A refusal FOR THE REVOKE and a refusal for anything else — a dropped
    /// socket, a signature the server would not verify, a connect timeout —
    /// collapse into the same `false`, which would pass for the absence of the
    /// mechanism as readily as for its presence.
    Future<String> authOutcome(EnrolledClient enrolled) async {
      final lookup =
          AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort)
            ..enrollmentId = enrolled.enrollmentId
            ..atChops = AtChopsImpl(AtChopsKeys.create(
              AtEncryptionKeyPair.create(
                  enrolled.keys.defaultEncryptionPublicKey!.toString(), ''),
              AtPkamKeyPair.create(enrolled.keys.apkamPublicKey!.toString(),
                  enrolled.keys.apkamPrivateKey!.toString()),
            ));
      try {
        final accepted =
            await lookup.pkamAuthenticate(enrollmentId: enrolled.enrollmentId);
        return accepted ? 'accepted' : 'refused without a reason';
      } catch (e) {
        return '$e';
      } finally {
        await lookup.close();
      }
    }

    /// Whether an outcome is the atServer refusing BECAUSE the enrollment is
    /// revoked, which is the only refusal this test may pass on.
    bool refusedAsRevoked(String outcome) =>
        outcome.contains('AT0027') && outcome.contains('is revoked');

    expect(await authOutcome(doomed.enrolled), 'accepted',
        reason: 'the control arm for the credential: the keypair genuinely '
            'authenticates before the revoke, so its refusal afterwards is '
            'the revoke and not a broken fixture');

    final before = await VerbEnrollmentDirectory(keeper.enrolled.client)
        .listForNamespace(namespace);
    expect(before.map((m) => m.enrollmentId),
        contains(doomed.enrolled.enrollmentId),
        reason: 'the control arm: without it the absence after the revoke is '
            'equally explained by a roster that never listed it');

    final revoked = await operator.enrolled.client.enrollmentService!.revoke(
        EnrollmentRequestDecision.revoked(
            doomed.enrolled.enrollmentId, atSign));

    // The acknowledgement. An `error:` response throws out of the line above,
    // but a `data:` response whose status is anything other than `revoked`
    // would otherwise pass silently, and then "the credential still works" is
    // equally explained by the revoke never having taken.
    expect(revoked.enrollmentId, doomed.enrolled.enrollmentId,
        reason: 'the atServer acknowledged a different enrollment than the '
            'one this test then waits to see refused');
    expect(revoked.enrollmentStatus, EnrollmentStatus.revoked,
        reason: 'the atServer ACKed the revoke without moving the record to '
            'revoked — so a credential that still works is the revoke not '
            'taking, not a visibility lag');

    /// The status the atServer reports for [id], read off `enroll:list`.
    ///
    /// Asks for EVERY status by name: a single-status filter does not answer
    /// "is it revoked?", and a reading taken that way looks like an answer.
    Future<String> statusOf(String id) async {
      final raw =
          await operator.enrolled.client.getRemoteSecondary()!.executeCommand(
              'enroll:list:{"enrollmentStatusFilter":'
              '["pending","approved","denied","revoked","expired"]}\n',
              auth: true);
      final body = raw!.replaceFirst('data:', '').trim();
      final at = body.indexOf('"$id.');
      if (at < 0) return 'ABSENT from the roster';
      final tail = body.substring(at);
      final s = tail.indexOf('"status"');
      return s < 0
          ? 'listed, no status field'
          : tail.substring(s, s + 26).replaceAll('"', '').replaceAll('\n', ' ');
    }

    // NOTE: `statusOf` feeds the failure message and nothing else. What
    // `enroll:list` returns for a revoked record is unreliable — asserting on
    // it fails intermittently for a reason unrelated to the property under
    // test. The revoke acknowledgement above is the gate.

    // NOTE: the revoked enrollment's own client holds a live authenticated
    // connection carrying its id, so leaving it open would hold open the very
    // thing this waits to see expire. The lost-laptop case is a keyfile in
    // someone else's hands, not a session still running.
    await doomed.enrolled.client.stop();

    // NOTE: the refusal is IMMEDIATE — the non-error revoke response means the
    // credential is already unavailable — so the retries below cover the
    // transport and nothing else. An acceptance fails on the spot rather than
    // being waited out, which would tolerate exactly the lost-laptop window
    // this denies.

    /// What the atServer says about [enrollmentId] right now, for a failure
    /// message.
    Future<String> serverViewOf(String enrollmentId) async {
      try {
        final served = await servedApkamKeyFor(enrollmentId);
        final held = doomed.enrolled.keys.apkamPublicKey!.toString();
        return 'server says [${await statusOf(enrollmentId)}]; '
            'apkamPubKey on the record ${served == held ? "MATCHES" : "DIFFERS FROM"} '
            'the key this test presented '
            '(record ${served?.substring(0, 12) ?? "absent"}…, '
            'presented ${held.substring(0, 12)}…)';
      } catch (e) {
        return 'server view unavailable: $e';
      }
    }

    var outcome = await authOutcome(doomed.enrolled);
    for (var i = 0; i < 4 && !refusedAsRevoked(outcome); i++) {
      if (outcome == 'accepted') {
        fail('a revoked enrollment authenticated on a fresh connection after '
            'the atServer acknowledged the revoke. Revocation is immediate — '
            'the non-error revoke response means the credential is already '
            'unavailable — so this is the fixture presenting a credential '
            'that is not the revoked enrollment\'s. ${await serverViewOf(doomed.enrolled.enrollmentId)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      outcome = await authOutcome(doomed.enrolled);
    }
    expect(refusedAsRevoked(outcome), isTrue,
        reason: 'the refusal must be the revoke and not something else that '
            'also fails. The atServer got: $outcome');

    expect(await authOutcome(keeper.enrolled), 'accepted',
        reason: 'and the sibling enrollment is untouched');

    // NOTE: the atServer serves enroll:listns through an enrollment cache that
    // the control arm's read above populates, so the roster is polled rather
    // than read once. The bound keeps this an assertion rather than a wait: a
    // roster that never catches up is a real defect, because a revoked
    // enrollment other holders still see is one they will still push secrets
    // to and still answer pulls from.
    var after = <String>[];
    for (var i = 0; i < 20; i++) {
      after = (await VerbEnrollmentDirectory(keeper.enrolled.client)
              .listForNamespace(namespace))
          .map((m) => m.enrollmentId)
          .toList();
      if (!after.contains(doomed.enrolled.enrollmentId)) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(after, isNot(contains(doomed.enrolled.enrollmentId)),
        reason: 'enroll:listns returns APPROVED enrollments only, and that is '
            'the whole enforcement: a revoked enrollment is skipped by every '
            'push and refused by every serve, on holders that have never '
            'heard of the rotation that excluded it');
    expect(after, contains(keeper.enrolled.enrollmentId),
        reason: 'and nobody else is affected');
  });

  test(
      'UC-A5.3 · revokeEnrollmentAndRotate revokes first, then supersedes the '
      'generation the revoked enrollment held', () async {
    // NOTE: its OWN namespace, because this needs a genuine cold start — the
    // owner retains the private for the superseded generation only if it
    // minted it, and on a warm namespace `mintAndPublish` ADOPTS the live
    // generation and files nothing. A sub-namespace of `buzz`, so the same
    // grant satisfies the atServer's write gate; the target is granted it
    // explicitly, because revokeEnrollmentAndRotate rotates what the TARGET's
    // enrollment names.
    final ns = 'cmp$runId.$namespace';
    final owner = await holder('cmp-owner', namespaces: operatorGrants);
    final target = await holder('cmp-target', namespaces: {ns: 'rw'});

    final before = await owner.ring.mintAndPublish(ns);

    // NOTE: revokeEnrollmentAndRotate revokes FIRST, so a rotation refused by
    // the cooldown would leave the enrollment cut off but still holding the
    // live generation.
    await pastTheCooldown();

    final outcomes = await NskeyRotation(
      atClient: owner.enrolled.client,
      ring: owner.ring,
      privateFiling: owner.filing,
      sharing: owner.sharing,
    ).revokeEnrollmentAndRotate(target.enrolled.enrollmentId);

    expect(outcomes.map((o) => o.namespace), contains(ns));
    final rotated = outcomes.firstWhere((o) => o.namespace == ns);
    expect(rotated.supersededKid, before.nskeyKid);
    expect(rotated.excluded, {target.enrolled.enrollmentId});

    // The atServer's record, not this ring's memory: `currentPublic` here
    // would answer from the cache the rotation itself just wrote.
    expect((await owner.ring.publishedAdvertisement(atSign, ns))?.nskeyKid,
        rotated.advertisement.nskeyKid);
    // The revoke has already dropped this enrollment out of enroll:listns, so
    // the pull gets its chance and still comes up empty.
    await Future<void>.delayed(const Duration(seconds: 1));
    await owner.sharing.sweepOnce(fromRemote: true);
    await NskeyPrivateFiling(keysIo: target.io, atSign: atSign)
        .filePending(target.sharing.secretStore.listSecrets());
    expect(await target.filing.read(ns, rotated.advertisement.nskeyKid), isNull,
        reason: 'the revoked enrollment keeps what it already held — the '
            'rotation denies it NEW data, and denying it the old data is the '
            'content-key lever\'s job, not this one\'s');
    expect(await owner.filing.read(ns, before.nskeyKid), isNotNull,
        reason: 'while the owner still opens everything sealed to the '
            'superseded generation');
  });

  test(
      'UC-G2.5 · a revocation whose rotation did not happen is rotated at the '
      'next start', () async {
    // The backstop for the composed lever: `revokeEnrollmentAndRotate` revokes
    // and then rotates, and when the second half does not happen nothing else
    // notices — the revoked enrollment is off every roster and still holds the
    // live generation's private, so it goes on opening everything sealed under
    // it. Its own namespace, so the mint is a cold start rather than an
    // adoption.
    final ns = 'bck$runId.$namespace';
    final owner = await holder('bck-owner', namespaces: operatorGrants);
    final target = await holder('bck-target', namespaces: {ns: 'rw'});

    final before = await owner.ring.mintAndPublish(ns);
    await pastTheCooldown();

    // Revoked and NOT rotated: the half-finished state, produced by driving the
    // revoke alone rather than through the lever that composes the two.
    await owner.enrolled.client.enrollmentService!.revoke(
        EnrollmentRequestDecision.revoked(
            target.enrolled.enrollmentId, atSign));

    final seeding = NskeySeeding(
      atClient: owner.enrolled.client,
      ring: owner.ring,
      sharing: owner.sharing,
      privateFiling: owner.filing,
    );

    expect(await seeding.rotateIfRevoked(atSign, ns), isTrue,
        reason: 'the atServer reports a revocation touching this namespace '
            'later than the moment it stamped the advertisement, and that is '
            'the whole of what a client needs to decide alone');
    final after = await owner.ring.publishedAdvertisement(atSign, ns);
    expect(after?.nskeyKid, isNot(before.nskeyKid),
        reason: 'a fresh generation is published, which is what denies the '
            'revoked enrollment the keys protecting anything written now');

    // The control: the rotation took a fresh server stamp, so the same
    // revocation is no longer later than it and the next start rotates nothing.
    await pastTheCooldown();
    expect(await seeding.rotateIfRevoked(atSign, ns), isFalse);
    expect((await owner.ring.publishedAdvertisement(atSign, ns))?.nskeyKid,
        after?.nskeyKid);
  });
}
