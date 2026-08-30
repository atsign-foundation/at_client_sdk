// The substrate and the nskey surface are @experimental; driving them is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The nskey-private self-heal between two real APKAM enrollments.
///
/// The scenario is the ordinary second device: the namespace key was minted
/// and pushed before this enrollment existed, so it holds the *published*
/// generation's public half and none of the private. Before the self-heal
/// landed this was a dead end — the only delivery was the mint-time push, and
/// an enrollment created after the mint met `no nskey private held` with no
/// request, no retry and no recovery (decisions.md 38).
///
/// What is asserted is the outcome in the seeker's KEYFILE, not that a method
/// ran: the private a holder answered with must be filed durably and byte-
/// exact, the ring must serve it, and nothing may have re-minted — a heal
/// that "fixed" the seeker by rotating the namespace key would strand every
/// peer that had already fetched the old generation.
void main() {
  late AtClient approver;
  late String atSign;

  // Unique per run: the atServer refuses a second enrollment carrying an
  // (appName, deviceName) pair that already has one approved.
  final runId = DateTime.now().microsecondsSinceEpoch;

  // ⚠️ **Run-unique, and it has to be.** This file's premise is that the
  // HOLDER is the one that minted — "the wave the seeker missed" — so anything
  // else publishing an nskey for the same namespace first makes
  // `mintAndPublish` ADOPT that generation instead, leaving the holder without
  // the private half it is about to be asked for. That is correct production
  // behaviour (the mint election, decisions 105), so the test has to stop
  // racing rather than the code stop adopting. On a shared `buzz` it lost the
  // race to `self_enrollment_retrofit_live_test`, whose pqActive posture seeds
  // namespace keys, and the failure surfaced as this file's own precondition.
  final namespace = 'selfheal$runId';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo,
            posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  /// [atKeysIo] is the client's OWN keyfile, so the test observes exactly what
  /// the client's start-time self-heal files. With two separate stores the
  /// client's own sweep can consume an answer and file it where the test is
  /// not looking, and the assertion reads a null meaning "somebody else got
  /// there first".
  Future<EnrolledClient> enrol(String device, {AtKeysIo? atKeysIo}) =>
      enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        atKeysIo: atKeysIo,
      );

  test('an enrollment that missed the mint pulls the private from a holder',
      () async {
    // The holder exists and mints BEFORE the seeker does — which is the
    // scenario ("the wave the seeker missed") and also what keeps the test
    // honest. Every client runs the same self-heal from its own start, and a
    // start-time sweep consumes and DELETES the requests it finds; a holder
    // that started before the namespace existed has an empty store and would
    // eat the seeker's request while answering nothing. In production that
    // holder restarts with the private in its keyfile and primes it; here,
    // ordering the mint first is the equivalent.
    final holderIo = InMemoryAtKeysIo();
    await holderIo.write(atSign, AtKeys());
    final holder = await enrol('nskey-holder', atKeysIo: holderIo);

    final holderSharing = AtClientSecretSharing.forClient(holder.client);
    await holderSharing.register();

    final holderFiling = NskeyPrivateFiling(keysIo: holderIo, atSign: atSign);
    final holderRing =
        PublishedNskeyKeyRing(holder.client, privateFiling: holderFiling);
    final advertisement = await holderRing.mintAndPublish(namespace);
    final holderPrivate =
        await holderFiling.read(namespace, advertisement.nskeyKid);
    expect(holderPrivate, isNotNull,
        reason: 'the holder must itself hold what it will be asked for');

    final seekerIo = InMemoryAtKeysIo();
    await seekerIo.write(atSign, AtKeys());
    final seeker = await enrol('nskey-seeker', atKeysIo: seekerIo);
    expect(seeker.enrollmentId, isNot(holder.enrollmentId),
        reason: 'two distinct enrollments, or the request is a client asking '
            'itself, which the substrate declines — green for the refusal '
            'rather than the answer');
    final seekerSharing = AtClientSecretSharing.forClient(seeker.client);
    await seekerSharing.register();

    // The seeker's view: the published generation exists, the private does
    // not. Both checked, so the heal below provably has work to do.
    final seekerFiling = NskeyPrivateFiling(keysIo: seekerIo, atSign: atSign);
    final seekerRing =
        PublishedNskeyKeyRing(seeker.client, privateFiling: seekerFiling);
    final seen = await seekerRing.currentPublic(atSign, namespace);
    expect(seen?.nskeyKid, advertisement.nskeyKid,
        reason: 'the seeker must see the published generation, or the pull '
            'below has nothing to name');
    expect(
        await seekerRing.privateHalf(atSign, namespace, advertisement.nskeyKid),
        isNull,
        reason: 'the seeker must genuinely lack the private, or filing at the '
            'end proves nothing about acquiring it');

    // The holder "restarts": its in-memory store is re-primed from AtKeys, as
    // AtClientImpl does at every start. Without this the holder would answer
    // with nothing — its store is a transit buffer the mint never populated.
    expect(
        await NskeySeeding(
                atClient: holder.client,
                ring: holderRing,
                privateFiling: holderFiling)
            .hydrateStoreFromFiling(holderSharing),
        greaterThan(0),
        reason: 'the holder must prime its answerable holdings, or the pull '
            'below is asked into a void');

    // The heal: the exact call AtClientImpl makes at every start.
    final asked = await NskeySeeding(
      atClient: seeker.client,
      ring: seekerRing,
      privateFiling: seekerFiling,
    ).requestMissingPrivates(seekerSharing);
    expect(asked, contains(namespace),
        reason: 'the request must go out — a heal that silently decided '
            'nothing was missing is the initiator-less state this replaces');

    // The holder comes online and answers; the seeker collects. Both legs are
    // store-and-forward — these sweeps are "each device runs occasionally".
    await holderSharing.sweepOnce(fromRemote: true);
    await seekerSharing.sweepOnce(fromRemote: true);

    // The in-run filing is unawaited by design; give it a moment.
    var filed = await seekerFiling.read(namespace, advertisement.nskeyKid);
    for (var i = 0; i < 20 && filed == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      filed = await seekerFiling.read(namespace, advertisement.nskeyKid);
    }

    expect(filed, holderPrivate,
        reason: 'the private must reach the seeker\'s KEYFILE byte-exact — '
            'the secret store is an in-memory transit buffer, and a private '
            'stopping there is gone at the next restart');
    expect(
        await seekerRing.privateHalf(atSign, namespace, advertisement.nskeyKid),
        isNotNull,
        reason: 'and the ring must serve it, which is what makes the '
            'namespace readable');

    // No re-mint: the published generation is still the holder's. A heal that
    // rotated would strand every peer holding the old advertisement.
    expect((await seekerRing.currentPublic(atSign, namespace))?.nskeyKid,
        advertisement.nskeyKid);
  });

  test(
      'a client START primes what it holds, so it can answer without anyone '
      'driving it', () async {
    // The test above drives `hydrateStoreFromFiling` by hand, which proves the
    // mechanism and NOT that anything calls it. This proves the call: a client
    // built the way production builds one primes its own store during its own
    // construction, before the sweep that would otherwise consume other
    // enrollments' requests and answer them with nothing.
    //
    // On an atSign this file has not built a client for, and with the private
    // seeded BEFORE that first construction. Both matter: `AtClientImpl`
    // caches by `(atSign, enrollmentId)`, so a second client for a principal
    // is the first one handed back and its construction never runs again; and
    // an enrollment's own approval rewrites its keyfile, which would discard
    // anything seeded beforehand. A holder restarting with material already
    // in its keyfile is the production shape this reproduces.
    final other = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final startIo = InMemoryAtKeysIo();
    final seeded = AtKeys();
    const kid = 'startprime0000';
    final bytes = Uint8List.fromList(List<int>.generate(32, (i) => i));
    seeded.addKey(CryptographicMaterial(
      keyId: NskeyPrivateFiling.keyIdFor(namespace, kid),
      role: CryptographicMaterialRole.privateDecapsulation,
      algorithm: CryptographicMaterialAlgorithm.xWing,
      bytes: AtBytes(bytes),
      createdAt: DateTime.now().toUtc(),
    ));
    await startIo.write(other, seeded);

    final manager =
        await TestUtils.initAtClient(other, namespace, atKeysIo: startIo,
            posture: PqPosture.legacy);

    final sharing = AtClientSecretSharing.forClient(manager.atClient);
    final wanted = '${NskeyPrivateFiling.secretNamePrefix}$kid';
    var primed = sharing.secretStore
        .listSecrets(namespace: namespace)
        .any((s) => s.name == wanted);
    for (var i = 0; i < 40 && !primed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      primed = sharing.secretStore
          .listSecrets(namespace: namespace)
          .any((s) => s.name == wanted);
    }

    expect(primed, isTrue,
        reason: 'start must prime the store from what the keyfile holds. A '
            'holder that does not is deaf to every pull — and worse than '
            'deaf, because its start-time sweep consumes and DELETES the '
            'requests it cannot answer, so the requester loses its broadcast '
            'too. It must also work WITHOUT asking the atServer which '
            'namespaces this enrollment holds: that lookup needs services the '
            'client has not been given yet at construction time, and its '
            'failure is swallowed as "nothing to prime"');
  });
}
