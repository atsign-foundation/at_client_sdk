// The signing-root surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show pqSigningRootMintLockKey, pqSigningRootMintLockRecordName;
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// What keeps one root per atSign, observed on the wire rather than inferred.
///
/// It used to be the record: `PqSigningRoot` wrote `immutable = true` and the
/// design leaned on the atServer refusing a second create. `decisions.md` 101
/// moved that job to `_rootlock@<atSign>` — a short-ttl immutable self key —
/// because the root is an ordinary signing key, and advertising a successor
/// beside its retired predecessor is a rewrite that an immutable record makes
/// unimplementable.
///
/// So there are now two cross-tier claims to watch rather than one, and they
/// are the kind this branch has had wrong twice: that the record reaching the
/// atServer is **not** immutable, and that a second create of the lock **is**
/// refused. The second is the interlock; the first is what makes rotation
/// possible at all.
///
/// ⚠️ **Nothing here touches the root record — not a write, not a seed.** It
/// used to write one: a second create was safe to attempt precisely because
/// the atServer refused it. Now it would LAND, and `signing_root_pull_test`,
/// `signing_root_pull_two_enrollments_test` and
/// `enrollment_chain_link_live_test` all read that record on this same atSign
/// — the last of them MINTS it into its own keyfile, so a root published here
/// with a private nobody holds takes three of its rows down. The write mode is
/// proved on a scratch record carrying the root's own metadata instead, and
/// the loser-of-the-race row moved to `enrollment_chain_link_live_test.dart`,
/// which owns the root on this atSign and mints it legitimately.
///
/// The companion claim is that `public:__nskey.<ns>@owner` is mutable too, and
/// for the same reason. Asserting both in one file keeps the pattern visible:
/// neither key record is immutable, and both are minted behind a lock that is.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    atClient = manager.atClient;
  });

  Future<String> remote(String command) async =>
      (await atClient
          .getRemoteSecondary()!
          .executeCommand(command, auth: true)) ??
      '';

  test('the metadata the signing root is written with is mutable on the '
      'atServer', () async {
    // ⚠️ Deliberately NOT the root record itself, and not a seeded one either.
    // With the record mutable a probe write LANDS, and a root published here
    // with a private nobody holds makes `enrollment_chain_link_live_test.dart`
    // — which mints the root into its own keyfile so the approval rows have a
    // private to convey — fail three assertions with no visible connection to
    // this file. Measured on 2026-08-15, not predicted: an earlier draft of
    // this test seeded a root and did exactly that.
    //
    // So the claim is made about the METADATA the root builder produces,
    // carried by a scratch record. `wire_literal_pins_test.dart` pins that
    // `pqSigningRootKey` produces exactly this metadata; this is that metadata
    // going onto a live atServer and being written twice.
    final rootMetadata = PqSigningRoot(atClient).keyFor(atSign).metadata;
    final scratch = AtKey()
      ..key = 'rootwritemode${DateTime.now().microsecondsSinceEpoch}'
      ..sharedBy = atSign
      ..metadata = rootMetadata;

    for (final value in ['first', 'second']) {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = scratch
            ..value = value);
    }

    final stored = await remote('llookup:${scratch.toString()}\n');
    expect(stored.replaceFirst('data:', '').trim(), 'second',
        reason: 'an immutable record would have refused the second write and '
            'left "first" standing — which is what the root record itself did '
            'until decisions 101. A root that cannot be rewritten can never '
            'advertise a successor beside a retired predecessor, and the '
            'atServer makes immutability STICKY (at_metadata_builder '
            'preserves immutable == true whatever an update asks), so one '
            'written with the flag would be unrewritable by anyone, forever');

    final meta = await remote('llookup:meta:${scratch.toString()}\n');
    expect(
        (jsonDecode(meta.replaceFirst('data:', '').trim())
            as Map<String, dynamic>)['immutable'],
        isNot(true),
        reason: 'and the flag is absent in what the atServer actually stored, '
            'so the write above succeeded because of the metadata rather than '
            'in spite of it');
  });

  test('a second signing-root mint lock create is refused', () async {
    // The interlock itself, watched rather than assumed. This is the property
    // the record used to carry, so it is worth seeing the atServer issue the
    // refusal on the record that carries it now.
    final lockKey = pqSigningRootMintLockKey(atSign);
    expect(lockKey.key, pqSigningRootMintLockRecordName);

    Future<void> take() async =>
        atClient.getRemoteSecondary()!.executeVerb(
            UpdateVerbBuilder()
              ..atKey = lockKey
              ..value = DateTime.now().toUtc().toIso8601String());

    // A leftover from an earlier run of this file would make the FIRST take
    // the refused one and the test would pass for the wrong reason.
    await atClient.getRemoteSecondary()!.executeVerb(
        DeleteVerbBuilder()
          ..atKey = lockKey
          ..force = true);

    await take();
    try {
      // Named, not `anything`: a bare throwsA would pass if the write failed
      // for an unrelated reason — a malformed verb, an auth problem — and the
      // test would be green for the absence of the effect rather than for the
      // interlock.
      await expectLater(
          take(),
          throwsA(predicate((e) =>
              e is IllegalStateException &&
              '$e'.contains('Immutable records may not be updated'))),
          reason: 'the atServer refusing the second create IS the mint lock. '
              'Without it two privileged enrollments each read no root, each '
              'mint one, and the second overwrites the first — which the '
              'mutable record now permits');
    } finally {
      // Released, or this atSign cannot mint a root for the ttl — including
      // in any later file of the same run.
      await atClient.getRemoteSecondary()!.executeVerb(
          DeleteVerbBuilder()
            ..atKey = lockKey
            ..force = true);
    }

    // Control: the same client, the same verb, the same key — accepted once
    // the lock is released. Without this, the refusal above could be this
    // client being unable to write the record at all.
    await take();
    await atClient.getRemoteSecondary()!.executeVerb(
        DeleteVerbBuilder()
          ..atKey = lockKey
          ..force = true);
  });

  test('the published nskey is mutable, because rotation depends on it',
      () async {
    // The sibling of the first test: same atSign, same public namespace, same
    // requirement. Both key records are mutable and both are minted behind an
    // immutable lock; if "immutable" ever migrated back onto either record,
    // rotation would stop working on that one and nothing else would say so.
    final ns = 'rot${DateTime.now().microsecondsSinceEpoch}.$namespace';
    // Nothing releases a mint lock but its ttl, so the mint below holds it and
    // the rotation that follows is refused until it lapses. Shortened here
    // because the production `mintLockTtl` would make this test wait two
    // minutes; the refusal itself is asserted in nskey_rotation_live_test.
    const lockTtl = Duration(seconds: 5);
    final ring = PublishedNskeyKeyRing(atClient, lockTtl: lockTtl);

    // Seed, then rotate: the second write goes through the rotation lever
    // rather than a second mint, so what proves the record mutable is the
    // operation that actually depends on it being mutable.
    final first = await ring.mintAndPublish(ns);
    // A second past the ttl: the atServer starts counting when it stores the
    // record, after this client sent it.
    await Future.delayed(lockTtl + const Duration(seconds: 1));
    final second = (await ring.rotate(ns)).rotated;

    expect(second.nskeyKid, isNot(first.nskeyKid),
        reason: 'a rotation mints a NEW generation; if these match, the second '
            'publish was a no-op and this proves nothing about mutability');

    final resolved =
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, ns);
    expect(resolved?.nskeyKid, second.nskeyKid,
        reason: 'the advertisement must now name the new generation — an '
            'immutable nskey record would have pinned peers to the old key '
            'forever, which is rotation failing closed and silently');
  });
}
