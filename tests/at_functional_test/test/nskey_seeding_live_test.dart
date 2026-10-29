// The nskey surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Namespace-key seeding against a live atServer.
///
/// Asserts the outcome on the atServer rather than that a method was called:
/// after seeding, the advertisement is fetchable by the exact lookup a sender
/// would use, and the client holds the matching private. Only an enrollment
/// whose record carries a key package mints; the atSign's own credential,
/// `primary`, carries none and mints nothing.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.7
void main() {
  TestUtils.isolateStorage('nskey_seeding_live_test');
  late String atSign;
  late AtClient owner;
  final runId = DateTime.now().microsecondsSinceEpoch;
  // NOTE: a namespace nothing has minted for, so the first seed provably does
  // work. Against a shared one the seed would adopt an existing key and every
  // assertion below would hold for the absence of seeding.
  final namespace = 'seed$runId';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    owner = (await TestUtils.initAtClient(atSign, namespace,
            atKeysIo: keysIo, posture: legacyPlusPqProviders))
        .atClient;
    await AtClientSecretSharing.forClient(owner).register();
  });

  test('a client on the atSign\'s own credential mints nothing', () async {
    final ring = PublishedNskeyKeyRing(owner);
    final seeding = NskeySeeding(
        atClient: owner,
        ring: ring,
        sharing: AtClientSecretSharing.forClient(owner),
        privateFiling: ring.privateFiling);
    expect(owner.enrollmentId, isNull,
        reason: 'the precondition: this client runs on the demo keys, which '
            'name no enrollment, so it authenticates as primary');
    expect(await seeding.authorisedNamespaces(), contains(namespace),
        reason: 'it is authorised for the namespace, so a refusal below is '
            'about the key package and nothing else');

    expect(await seeding.seedNamespace(atSign, namespace),
        NskeySeedOutcome.noKeyPackage,
        reason: 'primary carries no key package, so no other enrollment '
            'could be conveyed the private');
    expect(await PublishedNskeyKeyRing(owner).currentPublic(atSign, namespace),
        isNull,
        reason: 'and nothing was published for peers to seal to');
  });

  test('seeding publishes an advertisement the owner can then resolve',
      () async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final enrolled = await enrolAndAuthenticate(
      approver: owner,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: legacyPlusPqProviders)
        ..namespace = namespace,
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: 'seeder-$runId',
      atKeysIo: io,
      namespaces: {namespace: 'rw'},
      storage: TestUtils.storage,
    );
    final atClient = enrolled.client;
    final sharing = AtClientSecretSharing.forClient(atClient);
    await sharing.register();
    final filing = NskeyPrivateFiling(keysIo: io, atSign: atSign);
    final ring = PublishedNskeyKeyRing(atClient, privateFiling: filing);
    NskeySeeding seeding() => NskeySeeding(
        atClient: atClient,
        ring: ring,
        sharing: sharing,
        privateFiling: filing);

    expect(await ring.currentPublic(atSign, namespace), isNull,
        reason: 'the precondition: nothing has minted for this namespace, so '
            'the seed below has real work to do');

    expect(await seeding().seed(), contains(namespace),
        reason: 'seed() must report that it minted THIS namespace. Without '
            'this the test would pass just as well against a namespace that '
            'was already seeded, which is the failure mode it exists to rule '
            'out');

    // NOTE: an exact lookup is the only way a published nskey is reachable; it
    // is absent from every scan.
    final resolved =
        await PublishedNskeyKeyRing(owner).currentPublic(atSign, namespace);
    expect(resolved, isNotNull,
        reason: 'after seeding, the namespace must have a published '
            'advertisement — without one no sender can seal to this atSign');
    expect(resolved!.publicKey, isNotEmpty);

    final private =
        await ring.privateHalf(atSign, namespace, resolved.nskeyKid);
    expect(private, isNotNull,
        reason: 'the client must hold the private for the generation it just '
            'advertised, or it has invited traffic it cannot read');

    // Idempotent: a second start must adopt the existing advertisement, since
    // rotating here would strand every peer holding the old generation.
    expect(await seeding().seed(), isEmpty,
        reason: 'seeding is run at every start; if it re-minted each time, an '
            'atSign would rotate its namespace keys on every launch and no '
            'sender could keep up');
    expect(
        (await PublishedNskeyKeyRing(owner).currentPublic(atSign, namespace))
            ?.nskeyKid,
        resolved.nskeyKid,
        reason: 'and the advertisement is the same generation as before');
  });
}
