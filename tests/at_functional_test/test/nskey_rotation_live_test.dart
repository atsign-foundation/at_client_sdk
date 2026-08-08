// The substrate, the nskey surface and the rotation levers are @experimental;
// driving them is the point of this file.
// ignore_for_file: experimental_member_use

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
      ring: PublishedNskeyKeyRing(enrolled.client, privateFiling: filing),
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

  test(
      'UC-A5.2/A5.3 · a revoked enrollment cannot authenticate, and drops out '
      'of the roster every holder serves from', () async {
    final operator = await holder('rev-operator', namespaces: operatorGrants);
    final keeper = await holder('rev-keeper');
    final doomed = await holder('rev-doomed');

    // A fresh connection authenticating with the enrollment's own APKAM
    // keypair — what an attacker holding the lost keyfile would attempt.
    Future<bool> authenticatesAs(EnrolledClient enrolled) async {
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
        return await lookup.pkamAuthenticate(
            enrollmentId: enrolled.enrollmentId);
      } catch (_) {
        return false;
      } finally {
        await lookup.close();
      }
    }

    expect(await authenticatesAs(doomed.enrolled), isTrue,
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

    // Put the revoked enrollment's own client down before polling.
    //
    // It holds a live, authenticated connection carrying this enrollment id,
    // and the mechanism this test is probing is an atServer-side enrollment
    // cache. Leaving it open means the test may be holding open the very
    // thing it is waiting to see expire — and it is not what the scenario
    // describes either: the lost-laptop case is a keyfile in someone else's
    // hands, not a session still running.
    await doomed.enrolled.client.stop();

    // The credential first, because it is the primary claim — but polled with
    // a bound, and not merely to settle a flaky test.
    //
    // This was written asserting the refusal was immediate. On 2026-08-07 it
    // failed once in three consecutive full-suite runs: a FRESH connection
    // PKAM-authenticating with the revoked enrollment's own keypair was
    // ACCEPTED after `revoke()` had already returned, while the runs either
    // side of it refused it. So the atServer resolves an enrollment's state
    // for PKAM through the same cache `enroll:listns` is served from, and
    // revocation reaches both on the same eventual schedule — the control arm
    // above, which deliberately authenticates this enrollment beforehand, is
    // what populates that cache.
    //
    // Worth stating plainly rather than burying inside a poll: for a short
    // window after a revoke, a holder of the revoked keyfile can still
    // authenticate. The bound is what keeps this an assertion — if the
    // credential never stops working, this stays red and names the defect
    // that matters most in this file.
    var doomedAuthenticates = true;
    for (var i = 0; i < 20; i++) {
      doomedAuthenticates = await authenticatesAs(doomed.enrolled);
      if (!doomedAuthenticates) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(doomedAuthenticates, isFalse,
        reason: 'revocation cuts the one APKAM keypair this enrollment has — '
            'under 1:1:1 there is no per-pubkey delete, so revoking the '
            'enrollment IS revoking its key');
    expect(await authenticatesAs(keeper.enrolled), isTrue,
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
    final owner = await holder('cmp-owner', namespaces: operatorGrants);
    final target = await holder('cmp-target');

    final before = await owner.ring.mintAndPublish(namespace);

    final outcomes = await NskeyRotation(
      atClient: owner.enrolled.client,
      ring: owner.ring,
      privateFiling: owner.filing,
      sharing: owner.sharing,
    ).revokeEnrollmentAndRotate(target.enrolled.enrollmentId);

    expect(outcomes.map((o) => o.namespace), contains(namespace));
    final rotated = outcomes.firstWhere((o) => o.namespace == namespace);
    expect(rotated.supersededKid, before.nskeyKid);
    expect(rotated.excluded, {target.enrolled.enrollmentId});

    expect((await owner.ring.currentPublic(atSign, namespace))?.nskeyKid,
        rotated.advertisement.nskeyKid);
    // The pull gets its chance and still comes up empty. That is the whole
    // difference from a bare exclusion: the revoke has already dropped this
    // enrollment out of enroll:listns, so no holder will answer it and its own
    // credential no longer opens a connection to ask on.
    await Future<void>.delayed(const Duration(seconds: 1));
    await owner.sharing.sweepOnce(fromRemote: true);
    await NskeyPrivateFiling(keysIo: target.io, atSign: atSign)
        .filePending(target.sharing.secretStore.listSecrets());
    expect(await target.filing.read(namespace, rotated.advertisement.nskeyKid),
        isNull,
        reason: 'the revoked enrollment keeps what it already held — the '
            'rotation denies it NEW data, and denying it the old data is the '
            'content-key lever\'s job, not this one\'s');
    expect(await owner.filing.read(namespace, before.nskeyKid), isNotNull,
        reason: 'while the owner still opens everything sealed to the '
            'superseded generation');
  });
}
