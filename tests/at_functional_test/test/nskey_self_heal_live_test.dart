// The substrate and the nskey surface are @experimental; driving them is the
// point of this file.
// ignore_for_file: experimental_member_use

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
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  // Unique per run: the atServer refuses a second enrollment carrying an
  // (appName, deviceName) pair that already has one approved.
  final runId = DateTime.now().microsecondsSinceEpoch;

  Future<EnrolledClient> enrol(String device) => enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
      );

  test('an enrollment that missed the mint pulls the private from a holder',
      () async {
    final holder = await enrol('nskey-holder');
    final seeker = await enrol('nskey-seeker');
    expect(seeker.enrollmentId, isNot(holder.enrollmentId),
        reason: 'two distinct enrollments, or the request is a client asking '
            'itself, which the substrate declines — green for the refusal '
            'rather than the answer');

    final holderSharing = AtClientSecretSharing.forClient(holder.client);
    final seekerSharing = AtClientSecretSharing.forClient(seeker.client);
    await holderSharing.register();
    await seekerSharing.register();

    // The holder mints and publishes — the wave the seeker "missed". (Both
    // enrollments already exist here, so the mint-time push does reach the
    // seeker's key package as an envelope; the seeker never sweeps it into
    // its store, which is exactly the missed-push state a late device is in.)
    final holderIo = InMemoryAtKeysIo();
    await holderIo.write(atSign, AtKeys());
    final holderFiling = NskeyPrivateFiling(keysIo: holderIo, atSign: atSign);
    final holderRing =
        PublishedNskeyKeyRing(holder.client, privateFiling: holderFiling);
    final advertisement = await holderRing.mintAndPublish(namespace);
    final holderPrivate =
        await holderFiling.read(namespace, advertisement.nskeyKid);
    expect(holderPrivate, isNotNull,
        reason: 'the holder must itself hold what it will be asked for');

    // The seeker's view: the published generation exists, the private does
    // not. Both checked, so the heal below provably has work to do.
    final seekerIo = InMemoryAtKeysIo();
    await seekerIo.write(atSign, AtKeys());
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
}
