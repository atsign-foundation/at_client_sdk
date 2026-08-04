// The rollout surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The readiness flip, driven end to end against a live atServer.
///
/// The unit suite proves the negotiation decision; it cannot prove the thing
/// most likely to be wrong about it — that the marker is a real record on a
/// real atServer, fetchable by the exact lookup a sender uses, verifiable
/// against the publishing enrollment's `_apsk`, and that flipping it changes
/// what a *put* actually writes. Everything below the decision is production
/// code: the pre-pass, the content-key conveyance, the transformer, and the
/// stamp the record carries afterwards.
///
/// The two arms differ in one thing only — what the marker says. Both run the
/// same client against the same namespace with the same namespace key already
/// published, so a green result cannot come from a fixture that could never
/// have written the post-quantum path.
void main() {
  late String atSign;
  late AtClient atClient;
  late CryptoRollout rollout;
  late NskeyPrivateFiling filing;

  // A namespace nothing has ever advertised for, so the first publish below
  // provably does work. Against a shared namespace the "not ready" arm would
  // hold for whatever an earlier run left behind.
  final namespace = 'cap${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    atClient = manager.atClient;
    rollout = CryptoRollout(atClient);
    // The same durable store the client's own key ring reads from. Seeding
    // that files nowhere leaves a published key whose private lives only in
    // the seeding object — the write path could then seal to it and never
    // open what it wrote, which is exactly what this caught the first time it
    // ran.
    filing = NskeyPrivateFiling(keysIo: keysIo, atSign: atSign);
  });

  AtKey selfKey(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = atSign;

  test('a published marker is fetchable, verified, and starts at legacy-only',
      () async {
    expect(await rollout.advertisedBy(atSign, namespace), isNull,
        reason: 'the precondition: nothing has advertised for this namespace, '
            'so what follows is this run\'s work and not a leftover');

    expect(await rollout.publishNotReadyIfAbsent(namespace), isTrue);

    // Read back through the same path a *sender* uses: an exact lookup plus a
    // signature check against the publishing enrollment's `_apsk`. A marker
    // that only this process could see would negotiate nothing.
    expect(
        await rollout.advertisedBy(atSign, namespace), {legacyCryptoProviderId},
        reason: 'an upgraded client cannot speak for its siblings, so it '
            'advertises the one scheme it knows every build can read');

    expect(await rollout.publishNotReadyIfAbsent(namespace), isFalse,
        reason: 'seeding runs at every start; if it republished each time it '
            'would demote an atSign whose operator had declared it ready');
  });

  test('a put follows the marker, both ways', () async {
    // The namespace key has to exist for the ready arm to have anything to
    // seal to. Seeding is the production route to it, and it publishes the
    // marker alongside — which the previous test has already done here.
    final seeding = NskeySeeding(
        atClient: atClient,
        ring: PublishedNskeyKeyRing(atClient, privateFiling: filing),
        privateFiling: filing);
    expect(await seeding.seed(), contains(namespace),
        reason: 'without a published nskey the ready arm below would fail cold '
            'start rather than write the data path, and the test would pass '
            'for the wrong reason');

    // Arm 1 — the fleet reads legacy only.
    await rollout.publishNotReady(namespace);
    final beforeKey = selfKey('before');
    await atClient.put(beforeKey, 'written while not ready');

    expect((await atClient.get(beforeKey)).metadata?.appMetadata?.providerId,
        legacyCryptoProviderId,
        reason: 'this client holds the namespace key and can read the '
            'post-quantum path — the marker is the only thing stopping it '
            'writing one');

    // Arm 2 — the operator declares the fleet ready. Nothing else changes: same
    // client, same namespace, same key material.
    await rollout.declareReady(namespace);
    final afterKey = selfKey('after');
    await atClient.put(afterKey, 'written once ready');

    final stamped = (await atClient.get(afterKey)).metadata?.appMetadata;
    expect(stamped?.providerId, symmetricAesGcmCryptoProviderId,
        reason: 'the flip is a record on the atServer, not a new build');

    // And the content key really was conveyed, so the record is openable by
    // any enrollment holding the nskey private rather than only by the process
    // that wrote it.
    final ckKid = stamped?.additional?['ckKid'];
    expect(ckKid, isNotNull);
    final conveyance = await atClient.get(selfKey('$ckKid.__ck'));
    expect(conveyance.metadata?.appMetadata?.providerId, nskeyCryptoProviderId);

    // The record written under arm 1 still opens. Upgrading only ever adds
    // read capability, and a flip is not retroactive.
    expect((await atClient.get(beforeKey)).value, 'written while not ready');
  });

  test('withdrawing readiness returns writes to legacy', () async {
    await rollout.declareReady(namespace);
    expect(await rollout.advertisedBy(atSign, namespace),
        contains(symmetricAesGcmCryptoProviderId));

    await rollout.publishNotReady(namespace);

    final key = selfKey('withdrawn');
    await atClient.put(key, 'written after the withdrawal');

    expect((await atClient.get(key)).metadata?.appMetadata?.providerId,
        legacyCryptoProviderId,
        reason: 'an operator who declared too early, or who is bringing an old '
            'build back online, has to be able to stop new post-quantum '
            'writes — and the client that published the withdrawal must see it '
            'immediately rather than at the end of a cache window');
  });
}
