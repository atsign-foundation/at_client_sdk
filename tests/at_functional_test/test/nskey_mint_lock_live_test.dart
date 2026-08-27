// The nskey surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey, nskeyMintLockRecordName;
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The nskey mint interlock, watched on the wire rather than reasoned about.
///
/// Two claims, and until now both were **reasoned from the code**. The plan
/// recorded the second as "not observed — reasoned from the code, not
/// measured", and the first was covered only by a mock that models the
/// refusal — and a mock cannot test a refusal it does not model.
///
/// 1. **The atServer refuses a second create of `_nskeylock.<ns>@<atSign>`.**
///    That refusal *is* the lock. `pq_signing_root_mint_lock_test.dart` makes
///    the same observation for `_rootlock@<atSign>`; this is the other lock in
///    the design, and nothing had watched it.
/// 2. **A client meeting a lock held by another enrollment, with nothing
///    published, refuses to mint** rather than publishing a second generation
///    over whatever the holder is about to write.
///
/// ⚠️ **Run-unique namespace, and the lock is deleted in a `finally`.** The
/// lock is an immutable record with a two-minute ttl that nothing releases, so
/// a leftover would block minting for that namespace on this atSign for the
/// rest of the run — and against a shared namespace it would block every other
/// file too.
///
/// ⚠️ **The other holder is simulated by the lock's VALUE, not by a second
/// enrollment.** `MintLock` decides "is this my own lock" by comparing the
/// record's value against its own holder id, and `mintAndPublish` deliberately
/// passes `ownLockIsNotContention: true` so an enrollment re-entering its own
/// cooldown adopts rather than failing. Writing a foreign holder id is what
/// makes this client take the loser path — the path a genuine sibling would
/// put it on.
void main() {
  late AtClient atClient;
  late String atSign;
  // Its own namespace: this file takes and holds a mint lock, which is exactly
  // the state that stops another file minting.
  final namespace = 'mintlock${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: PqPosture.legacy);
    atClient = manager.atClient;
  });

  AtKey lockKey() =>
      nskeyMintLockKey(atSign, namespace, ttl: const Duration(minutes: 2));

  Future<void> release() async =>
      atClient.getRemoteSecondary()!.executeVerb(DeleteVerbBuilder()
        ..atKey = lockKey()
        ..force = true);

  Future<void> take(String holder) async =>
      atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = lockKey()
        ..value = holder);

  test('the atServer refuses a second create of the nskey mint lock', () async {
    expect(lockKey().key, nskeyMintLockRecordName,
        reason: 'the record this is about is the one the client composes, not '
            'a name spelled again here. The namespace rides the at-key\'s own '
            'namespace field rather than this one, which is what makes the '
            'run-unique namespace above isolate this file\'s lock from every '
            'other file\'s');

    // A leftover would make the FIRST take the refused one, and the test would
    // pass for the wrong reason.
    await release();

    await take('first-holder');
    try {
      await expectLater(
          take('second-holder'),
          throwsA(predicate((e) =>
              e is IllegalStateException &&
              '$e'.contains('Immutable records may not be updated'))),
          reason: 'this refusal IS the mint lock. Without it two enrollments '
              'each read no advertisement, each mint, and the second '
              'overwrites the first — stranding every peer that had already '
              'fetched it. Asserted on the atServer\'s own message rather than '
              'on any throw, so a write that failed for an unrelated reason '
              'cannot satisfy it');
    } finally {
      await release();
    }

    // The control. Without it the refusal above is equally well explained by
    // this client being unable to write that record at all.
    await take('after-release');
    await release();
  }, timeout: Timeout(Duration(minutes: 2)));

  test('two CONCURRENT mints by one enrolment publish one advertisement',
      () async {
    // The width-2 case. `ownLockIsNotContention` exists so an enrolment
    // re-entering its own cooldown LATER adopts rather than failing — but the
    // lock's holder token is the enrolment id, an identity rather than an
    // instance, so two racers of the SAME enrolment both read it back, both
    // see their own id, and both conclude they hold it.
    //
    // Reported by the at_talk demo session from a live wire capture: two
    // advertisements 7.5ms apart, different kid, the second overwriting the
    // first, both conveyed. A peer that fetched in that window holds a
    // generation the owner may no longer be able to open.
    //
    // ⚠️ It has to be LIVE. The unit fixture accepts every lock write, so the
    // refusal that triggers this never happens there — a mock cannot test a
    // refusal it does not model, and faking it would be testing the fake.
    //
    // Its own namespace: the arms above leave this file's namespace with a
    // published advertisement, which this one must not find.
    final raceNs = 'mintrace${DateTime.now().microsecondsSinceEpoch}';
    final raceLock =
        nskeyMintLockKey(atSign, raceNs, ttl: const Duration(minutes: 2));
    await atClient.getRemoteSecondary()!.executeVerb(DeleteVerbBuilder()
      ..atKey = raceLock
      ..force = true);

    // ONE ring, so ONE MintLock — which is what a client has: the PQ startup
    // step and `ensureReachable` both reach the bootstrap's single ring.
    final ring = PublishedNskeyKeyRing(atClient);
    expect(await ring.publishedAdvertisement(atSign, raceNs), isNull,
        reason: 'the precondition: nothing published, so both racers have '
            'real work and neither can adopt its way out');

    final both = await Future.wait(
        [ring.mintAndPublish(raceNs), ring.mintAndPublish(raceNs)]);

    try {
      expect(both[0].nskeyKid, both[1].nskeyKid,
          reason: 'both callers must end on ONE generation. Two different '
              'kids means two keypairs were minted and published, the second '
              'overwriting the first — and a peer that fetched between them '
              'is sealing to a generation whose private may be gone');
      final published = await ring.publishedAdvertisement(atSign, raceNs);
      expect(published!.nskeyKid, both[0].nskeyKid,
          reason: 'and what is on the atServer is that same generation, not a '
              'third thing');
    } finally {
      await atClient.getRemoteSecondary()!.executeVerb(DeleteVerbBuilder()
        ..atKey = raceLock
        ..force = true);
    }
  }, timeout: Timeout(Duration(minutes: 3)));

  test('a client that meets another holder\'s lock refuses to mint', () async {
    // Failure mode 2 of the abandoned-startup row, which was reasoned from the
    // code and never measured: a client that dies after its lock lands leaves
    // one held with nothing published, and a successor must not mint over
    // whatever the holder was about to write.
    await release();
    final ring = PublishedNskeyKeyRing(atClient);

    expect(await ring.publishedAdvertisement(atSign, namespace), isNull,
        reason: 'the precondition: nothing is published for this namespace, '
            'so the refusal below is the "lock held and nothing to adopt" '
            'case rather than an ordinary adoption');

    // A holder id that is not this client's, which is what a sibling
    // enrollment's lock looks like from here.
    await take('some-other-enrollment');
    try {
      await expectLater(
          ring.mintAndPublish(namespace),
          throwsA(predicate((e) =>
              e is StateError &&
              '$e'.contains('has published no advertisement yet'))),
          reason: 'refusing is deliberate: a put waiting on a namespace key '
              'fails loudly rather than hanging on a device that may have '
              'crashed mid-mint. Asserted on the message so an unrelated '
              'StateError cannot satisfy it');
      expect(await ring.publishedAdvertisement(atSign, namespace), isNull,
          reason: 'and it published NOTHING — the refusal is the point, and a '
              'client that threw after writing would have rotated the '
              'holder\'s generation away');
    } finally {
      await release();
    }

    // The control: the same client, the same call, accepted once the lock is
    // gone. Without it the refusal is equally well explained by this client
    // being unable to mint for this namespace at all.
    final minted = await ring.mintAndPublish(namespace);
    expect(minted.nskeyKid, isNotEmpty);
    expect(await ring.publishedAdvertisement(atSign, namespace), isNotNull);
    await release();
  }, timeout: Timeout(Duration(minutes: 3)));
}
