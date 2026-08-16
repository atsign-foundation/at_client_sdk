// The substrate, the nskey surface and the rotation levers are @experimental;
// driving them is the point of this file.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_rotation.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The two rotation levers, driven against a live atServer, and the revocation
/// they compose with.
///
/// The pair is the point: rotating the nskey **keypair** denies an enrollment
/// the keys that protect data written from now on, and leaves every earlier
/// content key readable; rotating the **content key** and deleting its
/// conveyance is what makes already-written data unreadable. Neither substitutes
/// for the other, and the unit tests can only assert that separately — here both
/// run against a real atServer that actually refuses a revoked credential and
/// actually stops serving a deleted record.
void main() {
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    // The SECOND atSign, not the first. These tests create eight enrollments
    // and REVOKE one, and both are shared state the rest of the suite reads:
    // every enroll:listns walks the whole roster, and a revoked enrollment's
    // _apsk is deleted for good. Run against the first atSign they slow every
    // later enrollment test down and leave a revoked record in the middle of
    // the suite's most-used identity. (Found the hard way — these three pass
    // alone and took two unrelated files down inside the full run.)
    atSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  // Unique per run: the atServer refuses a second enrollment carrying an
  // (appName, deviceName) pair that already has one approved, so fixed names
  // pass on a fresh virtualenv and collide on the second run against it.
  final runId = DateTime.now().microsecondsSinceEpoch;

  /// The mint lock's ttl for these tests, and it is not a speed-up.
  ///
  /// Nothing releases a mint lock but expiry, so the ttl is a **cooldown**:
  /// after a cold-start mint takes the lock, a rotation of the same namespace
  /// is refused until it lapses. That is the protocol, not a defect — but it
  /// means every rotation test here mints and then rotates inside the window,
  /// and at the production `mintLockTtl` each would sit for two minutes.
  ///
  /// Long enough that no mint here races its own expiry (a keygen, a keyfile
  /// write, a signature and two round trips), short enough to wait out. What
  /// the cooldown itself does is asserted separately, at this same ttl, in
  /// `a rotation inside the mint lock's cooldown is refused`.
  const shortLockTtl = Duration(seconds: 5);

  /// Waits until the lock a mint just took has expired.
  ///
  /// A second past the ttl, because the atServer starts counting when it
  /// stores the record — after this client sent it — so waiting exactly the
  /// ttl can land a moment early.
  Future<void> pastTheCooldown() =>
      Future.delayed(shortLockTtl + const Duration(seconds: 1));

  Future<EnrolledClient> enrol(String device,
          {AtKeysIo? atKeysIo, Map<String, String>? namespaces}) =>
      enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        atKeysIo: atKeysIo,
        namespaces: namespaces,
      );

  /// What revocation actually needs, which is NOT what rotation needs.
  /// Rotating is gated on `rw` for the namespace — the bar the atServer already
  /// enforces on the advertisement write, and a scoped device clears it.
  /// Revoking is gated on `__manage`, and a client without it cannot even
  /// enumerate the atSign's enrollments to find the one it means.
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

    final rotation = NskeyRotation(
      atClient: rotator.enrolled.client,
      ring: rotator.ring,
      privateFiling: rotator.filing,
      sharing: rotator.sharing,
    );

    // The mint above took the lock and did not release it, so the rotation
    // has to wait the cooldown out. Not a sleep to make a flake go away: the
    // refusal inside this window is asserted deliberately further down.
    await pastTheCooldown();

    final outcome = await rotation.rotateNamespaceKey(namespace,
        excludeEnrollmentIds: {excluded.enrolled.enrollmentId});

    expect(outcome.supersededKid, first.nskeyKid);
    expect(outcome.advertisement.nskeyKid, isNot(first.nskeyKid));
    expect(outcome.conveyedTo, greaterThan(0),
        reason: 'the survivor has a key package registered for this '
            'namespace, so the push must find somebody');

    // The atServer's own copy, read by an enrollment that did not do the
    // rotation. Reading the rotator's own memory would prove nothing about
    // what a peer will seal to.
    final published = await survivor.ring.currentPublic(atSign, namespace);
    expect(published?.nskeyKid, outcome.advertisement.nskeyKid,
        reason: 'the advertisement is OVERWRITTEN — that is what makes new '
            'content keys seal to the successor, and it is the only signal a '
            'peer ever gets that a rotation happened');

    // The survivor collects what was pushed and files it.
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

    // The exclusion, asserted where it actually bites: the roster the push
    // enumerates. `excludeEnrollmentIds` reaches `enroll:listns` and drops the
    // member before a single envelope is sealed to it.
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

    // And what the exclusion does NOT do, which is the reason
    // revokeEnrollmentAndRotate exists at all: a still-approved enrollment is
    // still a member of the namespace, so it can ask any holder for the
    // generation it can see published and be answered. The exclusion stopped
    // one client pushing; it could never bind a holder that has only the
    // atServer's word to go on. Only revocation removes it from every roster
    // and every serve — UC-A5.3 below is the composition that does.
    //
    // Not asserted here, deliberately. Whether that pull completes inside a
    // test depends on when a background self-heal happens to fire, so an
    // assertion either way is an assertion about a race: the first version of
    // this test claimed the excluded enrollment got nothing and passed once,
    // the second claimed it got the successor and passed once. The serve
    // itself IS pinned, deterministically, by the pull-flow group in
    // pairwise_secret_sharing_test.dart — a holder answers a requester the
    // roster lists and refuses one it does not.

    // The rotator retains the superseded private, so retained conveyances
    // sealed to it still open. Rotation replaces the key; it does not decrypt
    // or re-encrypt the past.
    expect(await rotator.filing.read(namespace, first.nskeyKid), firstPrivate);
    expect(await rotator.ring.privateHalf(atSign, namespace, first.nskeyKid),
        isNotNull);
  });

  test('a rotation inside the mint lock\'s cooldown is refused', () async {
    // The consequence of the winner never releasing the lock, asserted rather
    // than discovered. It cannot be a unit test: the interlock IS the
    // atServer refusing a second create of an immutable record, and a mocked
    // executeVerb accepts the second take happily — so every unit test of this
    // path is green whether or not the cooldown exists.
    final ns = 'cooldown$runId.$namespace';
    final owner = await holder('cooldown-owner');

    final minted = await owner.ring.mintAndPublish(ns);

    await expectLater(
        owner.ring.rotate(ns),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('holds the mint lock'))),
        reason: 'the ttl is the only release, so an election held moments ago '
            'is still in its cooldown. A rotation must fail here rather than '
            'adopt: adopting would have rotated nothing while reporting '
            'success, leaving the enrollment being rotated away from on the '
            'live generation');

    // The control, and it is what makes the refusal mean something: the same
    // client, the same namespace, the same call, accepted once the cooldown
    // has lapsed. Without it the failure above could be this enrollment being
    // unable to rotate at all.
    await pastTheCooldown();
    final rotated = (await owner.ring.rotate(ns)).rotated;
    expect(rotated.nskeyKid, isNot(minted.nskeyKid));
  });

  test(
      'UC-A5.2/A5.3 · a revoked enrollment cannot authenticate, and drops out '
      'of the roster every holder serves from',
      // Three full enrollments — each a submit, an approve and a
      // waitForApproval over the wire — plus a revoke and the roster reads.
      // The 30-second default is not a budget for that, and when a loaded
      // machine tips it over the row fails as a bare TimeoutException with
      // nothing to say about revocation, which reads as the mechanism under
      // test breaking. The sibling retrofit row carries 90 for the same
      // reason.
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

    // Distinct ids do NOT imply distinct keypairs. A keyfile carries one flat
    // apkamPublicKey/apkamPrivateKey slot, so two enrollments sharing an
    // AtKeysIo would both read whichever wrote last — and then "the revoked
    // credential still authenticates" would just be this test presenting a
    // live enrollment's key under a revoked enrollment's id. holder() gives
    // each its own InMemoryAtKeysIo precisely so that cannot happen; this
    // asserts it actually held.
    expect({
      operator.enrolled.keys.apkamPublicKey!.toString(),
      keeper.enrolled.keys.apkamPublicKey!.toString(),
      doomed.enrolled.keys.apkamPublicKey!.toString(),
    }, hasLength(3),
        reason: 'three enrollments sharing one APKAM keypair makes the '
            'credential arm below meaningless — whichever key it presents '
            'would belong to an enrollment nobody revoked');

    /// The APKAM public key the atServer holds for [enrollmentId], read off
    /// the roster rather than inferred from this process's own state.
    ///
    /// This is what makes the credential arm a statement about the revoke: if
    /// the key this test signs with is not the key the record names, the
    /// atServer's answer is about a key mismatch and says nothing about
    /// revocation either way.
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
    /// Returning `true`/`false` is what made this row uninterpretable. A
    /// refusal FOR THE REVOKE and a refusal for anything else — a dropped
    /// socket, a signature the server would not verify, a connect timeout —
    /// all collapsed into the same `false` the revoke produces, so the
    /// assertion passed for the ABSENCE of the mechanism as readily as for
    /// its presence, and told nobody which had happened when it did not.
    /// This row has been diagnosed three times and the diagnosis has moved
    /// every time, because the sentence that settles it was being discarded
    /// here.
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
    /// revoked, which is the only refusal this row may pass on.
    bool refusedAsRevoked(String outcome) =>
        outcome.contains('AT0027') && outcome.contains('is revoked');

    expect(await authOutcome(doomed.enrolled), 'accepted',
        reason: 'the control arm for the credential: the keypair genuinely '
            'authenticates before the revoke, so its refusal afterwards is '
            'the revoke and not a broken fixture');

    // Both are visible to each other before the revoke — the precondition
    // that makes the disappearance below mean something.
    final before = await VerbEnrollmentDirectory(keeper.enrolled.client)
        .listForNamespace(namespace);
    expect(before.map((m) => m.enrollmentId),
        contains(doomed.enrolled.enrollmentId),
        reason: 'the control arm: without it the absence after the revoke is '
            'equally explained by a roster that never listed it');

    final revoked = await operator.enrolled.client.enrollmentService!.revoke(
        EnrollmentRequestDecision.revoked(
            doomed.enrolled.enrollmentId, atSign));

    // Assert the acknowledgement, which this test used to discard.
    //
    // The revoke IS awaited all the way to the socket read, and an `error:`
    // response would throw out of the line above — but a `data:` response
    // whose status is anything other than `revoked` was silently accepted.
    // Without these two lines "the credential still works" is equally
    // explained by the revoke never having taken, and attributing it to an
    // atServer cache is a guess. Making that distinction is the whole point:
    // it is what turns the failure below into evidence about the atServer
    // rather than about this test.
    expect(revoked.enrollmentId, doomed.enrolled.enrollmentId,
        reason: 'the atServer acknowledged a different enrollment than the '
            'one this test then waits to see refused');
    expect(revoked.enrollmentStatus, EnrollmentStatus.revoked,
        reason: 'the atServer ACKed the revoke without moving the record to '
            'revoked — so a credential that still works is the revoke not '
            'taking, not a visibility lag');

    // And the record itself, re-read. The two assertions above read the ACK,
    // which is genuinely the atServer's reply rather than an echo — but it is
    // the reply to the write, not the state afterwards. Re-reading is what
    // separates "the revoke did not take" from "the revoke took and the
    // credential works anyway", and only the second is a statement about the
    // atServer's enrollment handling.
    // `Enrollment` carries no status field, so the read-back goes through the
    // atServer's own status FILTER: the revoked list must contain it and the
    // approved list must not. Both arms, because a filter that ignored its
    // argument would satisfy either one alone.
    /// The status the atServer reports for [id], read off `enroll:list`.
    ///
    /// Asks for EVERY status by name. A single-status filter does not answer
    /// "is it revoked?": measured against a genuinely revoked enrollment,
    /// `["revoked"]` alone returned an empty map and `["approved"]` alone
    /// returned the record, while the all-statuses list reported
    /// `"status":"revoked"` correctly. A reading taken the first way is worse
    /// than none, because it looks like an answer.
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

    // NOT asserted, deliberately. Reading the record back through
    // `enroll:list`'s status filter looked like the way to prove the revoke
    // landed, but `enroll:list` was never probed for what it returns for a
    // revoked record, and asserting on it returned an EMPTY list in 2 of 3
    // runs while the revoke ACK was correct every time. Whether that is a
    // listing lag, a filter this client sends wrongly, or a verb that simply
    // does not list revoked records is unknown — and an unprobed assertion
    // that fails intermittently is worse than none, because it fails the row
    // for a reason unrelated to the property under test.
    //
    // The revoke ACK above is the gate. This reading survives only in the
    // failure message below, where a wrong value costs nothing.

    // Put the revoked enrollment's own client down before polling.
    //
    // It holds a live, authenticated connection carrying this enrollment id,
    // and the mechanism this test is probing is an atServer-side enrollment
    // cache. Leaving it open means the test may be holding open the very
    // thing it is waiting to see expire — and it is not what the scenario
    // describes either: the lost-laptop case is a keyfile in someone else's
    // hands, not a session still running.
    await doomed.enrolled.client.stop();

    // The credential first, because it is the primary claim.
    //
    // The refusal is IMMEDIATE, and this asserts that rather than polling for
    // it. The atServer's own functional suite proves the same property from
    // the other side — enrol, approve, authenticate, revoke without force,
    // then two fresh connections both refused with `error:AT0027` — so a
    // client that keeps authenticating is not a visibility lag to be waited
    // out. There is nothing to wait for.
    //
    // What was here before polled twenty times over ten seconds and passed as
    // soon as any attempt stopped succeeding. That tolerates a revoked
    // credential authenticating for ten seconds after the atServer has
    // acknowledged the revoke, which is the lost-laptop window this row exists
    // to deny. It also passed on ANY refusal, so a dropped socket read as
    // proof of revocation.
    //
    // Retries here cover the transport and nothing else: an outcome that is
    // neither acceptance nor an AT0027 refusal gets a few more chances, an
    // acceptance fails immediately, and whatever it kept getting is named in
    // the failure rather than reduced to a boolean.
    /// What the atServer says about [enrollmentId] right now, for a failure
    /// message.
    ///
    /// Revocation is immediate — the non-error revoke response means the
    /// enrollment is already unavailable for authentication — so an
    /// acceptance here is not a propagation window. It means the credential
    /// that authenticated was not this enrollment's. That is a statement
    /// about the fixture, and these three readings are what tell which part
    /// of it: whether the record moved, and whether the key being presented
    /// is still the key the record names.
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

    // Then the roster. Polled rather than read once: the atServer serves
    // enroll:listns through an enrollment cache, and a roster read taken
    // BEFORE the revoke — which the control arm above deliberately takes —
    // populates it. Observed converging within a second or two, and observed
    // still stale on the first read immediately after the revoke. The bound
    // is what keeps this an assertion rather than a wait: if the roster never
    // catches up, this stays red and names a real defect, because a revoked
    // enrollment that other holders still see is one they will still push
    // secrets to and still answer pulls from.
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
    // Its OWN namespace, because this test needs a genuine cold start: it
    // asserts that the owner retains the private for the superseded
    // generation, which is only true if the owner minted it. `buzz` is already
    // warm by now — UC-A5.1(b) above minted and rotated it — so a
    // `mintAndPublish` here ADOPTS that generation and files nothing, and the
    // retention assertion has nothing to find. It passed before only because
    // the mint used to overwrite the sibling test's key rather than adopt it,
    // which is exactly the overwrite the under-lock re-read now prevents.
    //
    // A sub-namespace of `buzz`, so the atServer's write gate is satisfied by
    // the same grant; the target is granted it explicitly, because
    // revokeEnrollmentAndRotate rotates what the TARGET's enrollment names.
    final ns = 'cmp$runId.$namespace';
    final owner = await holder('cmp-owner', namespaces: operatorGrants);
    final target = await holder('cmp-target', namespaces: {ns: 'rw'});

    final before = await owner.ring.mintAndPublish(ns);

    // Same cooldown as above — and here it matters more, because
    // revokeEnrollmentAndRotate revokes FIRST: a rotation refused by the
    // cooldown would leave the enrollment cut off but still holding the live
    // generation, which is the partial state its own severe log names.
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

    expect((await owner.ring.currentPublic(atSign, ns))?.nskeyKid,
        rotated.advertisement.nskeyKid);
    // The pull gets its chance and still comes up empty. That is the whole
    // difference from a bare exclusion: the revoke has already dropped this
    // enrollment out of enroll:listns, so no holder will answer it and its own
    // credential no longer opens a connection to ask on.
    await Future<void>.delayed(const Duration(seconds: 1));
    await owner.sharing.sweepOnce(fromRemote: true);
    await NskeyPrivateFiling(keysIo: target.io, atSign: atSign)
        .filePending(target.sharing.secretStore.listSecrets());
    expect(await target.filing.read(ns, rotated.advertisement.nskeyKid),
        isNull,
        reason: 'the revoked enrollment keeps what it already held — the '
            'rotation denies it NEW data, and denying it the old data is the '
            'content-key lever\'s job, not this one\'s');
    expect(await owner.filing.read(ns, before.nskeyKid), isNotNull,
        reason: 'while the owner still opens everything sealed to the '
            'superseded generation');
  });
}
