@Tags(['pq'])
library;

// The PQ bootstrap is @experimental; reaching for it is the point here, since
// only the client's own bootstrap builds the wiring an application gets.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_chops/at_chops.dart' show XWingKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// The nskey data path across two real atSigns.
///
/// On an inbound record the *record* belongs to the sender but the envelope is
/// sealed to the **recipient's** nskey, so a reader deriving the key from
/// `sharedBy` asks its ring for the sender's namespace private — which it will
/// never hold. Self data hides that entirely, because there the two atSigns
/// coincide.
void main() {
  late String alice;
  late String bob;
  late String authType;
  final namespace = TestConstants.namespace;
  // NOTE: one manager per atSign for the whole file, so alice and bob are live
  // at once and nothing switches. Through the singleton, bringing one up stops
  // the other, and a stopped client's services throw.
  final managers = <String, AtClientManager>{};

  setUpAll(() {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    authType = ConfigUtil.getYaml()['authType'];
  });

  /// Bring an atSign up on the nskey data path, minting and publishing its
  /// namespace key. The ring needs the client, and the client's preference is
  /// read live, so the config is set once both exist.
  Future<({AtClient client, PublishedNskeyKeyRing ring})> nskeyClient(
      String atSign) async {
    final manager = managers.putIfAbsent(atSign, () => AtClientManager(atSign));
    await TestSuiteInitializer.getInstance().testInitializer(
        atSign, namespace, authType,
        posture: legacyPlusPqProviders, manager: manager);
    final client = manager.atClient;

    // The client's OWN ring, not one built here: it carries the
    // `askOnReadMiss` gate, and it is the one instance whose `privatesFiled`
    // events the notification service is subscribed to. `TestSuiteInitializer`
    // supplies its key source at first construction.
    final ring = (client as AtClientImpl).pqBootstrap!.ring;
    client.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    await ring.mintAndPublish(namespace);
    await E2ESyncService.getInstance().syncData(client.syncService);
    return (client: client, ring: ring);
  }

  String uniqueKey(String prefix) =>
      '$prefix.${DateTime.now().microsecondsSinceEpoch}';

  // Cross-atSign on purpose: the metadata serializer has a unit test, but only
  // two atSigns prove a record's providerId survives the whole write path,
  // sync push included.
  test('alice shares with bob, and bob reads it with his own nskey private',
      () async {
    // Both sides mint and publish eagerly — no promotion step, so bob is
    // reachable the moment he has ever used the namespace.
    final bobSide = await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);

    final keyName = uniqueKey('treaty');
    const plaintext = 'the treaty text';
    final shared = AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;

    // Alice has no content key for @bob, so this only succeeds if the pre-pass
    // discovers bob's published nskey by plookup and conveys a CK sealed to it.
    expect(await aliceSide.client.put(shared, plaintext), true);
    await E2ESyncService.getInstance().syncData(aliceSide.client.syncService);

    // The value cites a CK and carries no key.
    final asWritten = await aliceSide.client.get(shared);
    final ckKid = asWritten.metadata?.appMetadata?.additional?['ckKid'];
    expect(asWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId);
    expect(ckKid, isNotNull);

    // Alice cannot open the conveyance she just wrote: it is sealed to BOB's
    // nskey and she holds no private for it.
    await expectLater(
      aliceSide.client.get(AtKey()
        ..key = '$ckKid.__ck'
        ..namespace = namespace
        ..sharedWith = bob
        ..sharedBy = alice),
      throwsA(isA<AtException>()),
      reason: 'the sender must not be able to decapsulate a CK she sealed to '
          'the recipient — only bob can',
    );

    // Bob reads: the record is alice-owned, so a reader keying its ring by
    // sharedBy would look up ALICE's private and fail. It resolves because the
    // nskey owner is sharedWith.
    await E2ESyncService.getInstance().syncData(bobSide.client.syncService);

    final received = await bobSide.client.get(AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice);
    expect(received.value, plaintext,
        reason: 'bob opens the CK with HIS nskey private, not the sender\'s');

    // And he opened it with the generation he had advertised — which is what
    // alice discovered by plookup rather than being told.
    expect(received.metadata?.appMetadata?.additional?['ckKid'], ckKid);
  });

  /// Notify, on the nskey path, across two atSigns.
  ///
  /// Both notify entry points pick a provider, and a provider chosen before
  /// the namespace is filled in from the preference falls back to the legacy
  /// provider while `put` on the identical key uses nskey.
  ///
  /// The failure mode is that the *wrong thing succeeds*: a legacy-encrypted
  /// notification is delivered and decrypted perfectly well, so no ordinary
  /// notify test can see the downgrade. Only the provider id distinguishes it.
  test('a notification to bob is nskey-encrypted, not silently legacy',
      () async {
    final bobSide = await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);

    final keyName = uniqueKey('alert');
    const plaintext = 'the treaty is signed';

    // Deliberately namespace-less: the preference supplies it. That is the
    // shape most callers use, and the one the nskey providers decline if a
    // provider is chosen before the namespace arrives.
    final notifyKey = AtKey()
      ..key = keyName
      ..sharedWith = bob
      ..sharedBy = alice;

    final result = await aliceSide.client.notificationService
        .notify(NotificationParams.forUpdate(notifyKey, value: plaintext));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered);

    // The preference namespace was applied before the provider was chosen —
    // this is the data provider and not `legacy`.
    expect(notifyKey.namespace, namespace,
        reason: 'the preference namespace must be applied to the key');
    expect(notifyKey.metadata.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'a notification must reach the same provider a put would for '
            'this key — falling back to legacy here is a silent downgrade');

    // And on the wire: the recipient's atServer holds the frame, and the value
    // it holds is ciphertext, not the plaintext alice passed.
    final listed = (await bobSide.client.notifyList(regex: keyName))
        .replaceFirst('data:', '');
    final frames = jsonDecode(listed) as List;
    expect(frames, isNotEmpty, reason: 'the notification must have arrived');
    expect(frames.first['from'], alice);
    expect(frames.first['value'], isNot(plaintext),
        reason: 'the delivered value must be encrypted');
  }, timeout: Timeout(const Duration(minutes: 2)));

  test('the sender keeps a self-copy under a different content key', () async {
    // Bob must have published his nskey before alice can seal a CK to it; the
    // handle itself is unused here.
    await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);

    final shared = AtKey()
      ..key = uniqueKey('memo')
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;
    expect(await aliceSide.client.put(shared, 'for bob'), true);

    final selfKey = AtKey()
      ..key = uniqueKey('memo')
      ..namespace = namespace
      ..sharedBy = alice;
    expect(await aliceSide.client.put(selfKey, 'for me'), true);

    final toBobCk = (await aliceSide.client.get(shared))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'];
    final selfCk = (await aliceSide.client.get(selfKey))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'];

    expect(toBobCk, isNot(selfCk),
        reason: 'content keys are scoped per recipient — bob\'s CK must never '
            'become the key alice encrypts her own data under, or holding one '
            'would open the other');
  });

  /// A **nested** namespace across two atSigns.
  ///
  /// The sender resolves against the recipient's *published* advertisements, so
  /// the walk here is real `plookup` traffic rather than a local ring lookup.
  /// The app namespace is deliberately multi-segment: a composed
  /// `__rr.<id>.app_1.<ns>` splits to `<ns>`, so a single-segment app namespace
  /// would let the split land on the right answer by coincidence.
  test('alice shares with bob under a composed namespace', () async {
    final appNs = 'app_1.$namespace';
    final composed = '__rr.item123.app_1.$namespace';

    // Both mint at the multi-segment app namespace; neither mints per item.
    final bobSide = await nskeyClient(bob);
    await bobSide.ring.mintAndPublish(appNs);
    final aliceSide = await nskeyClient(alice);
    await aliceSide.ring.mintAndPublish(appNs);

    final shared = AtKey()
      ..key = uniqueKey('memo')
      ..namespace = composed
      ..sharedWith = bob
      ..sharedBy = alice;

    expect(await aliceSide.client.put(shared, 'the treaty text'), true);
    await E2ESyncService.getInstance().syncData(aliceSide.client.syncService);

    final asWritten = await aliceSide.client.get(shared);
    final meta = asWritten.metadata?.appMetadata?.additional;
    expect(meta?['ns'], composed,
        reason: 'the value states its own namespace; the wire string would '
            'have reported "$namespace"');
    expect(meta?['ckNs'], appNs,
        reason: 'the walk found bob\'s key one level up, and the content key '
            'lives there');

    await E2ESyncService.getInstance().syncData(bobSide.client.syncService);

    final received = await bobSide.client.get(AtKey()
      ..key = shared.key
      ..namespace = composed
      ..sharedWith = bob
      ..sharedBy = alice);
    expect(received.value, 'the treaty text',
        reason: 'bob opens the CK with the private for the namespace the '
            'record names, not the one its key string implies');
  }, timeout: Timeout(const Duration(minutes: 2)));

  /// The mechanism revocation rests on.
  ///
  /// A sender never sees a recipient's decapsulation fail, so re-`plookup`ing
  /// the advertisement is the **only** way it learns the recipient rotated.
  /// Without it a peer keeps sealing to a generation a revoked enrollment can
  /// still open, and revocation silently fails for everything inbound.
  test('bob rotates, and alice\'s next write seals to the new generation',
      () async {
    final bobSide = await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);

    final before = AtKey()
      ..key = uniqueKey('before')
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;
    expect(await aliceSide.client.put(before, 'first'), true);
    final firstCk =
        (await aliceSide.client.get(before)).metadata?.appMetadata?.additional;

    // Bob rotates. Alice is told nothing — the whole point.
    final rotated = await bobSide.ring.mintAndPublish(namespace);
    expect(rotated.nskeyKid, isNotNull);

    // Alice writes again with a ring that has never seen the new generation.
    final aliceAfter = await nskeyClient(alice);
    final after = AtKey()
      ..key = uniqueKey('after')
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;
    expect(await aliceAfter.client.put(after, 'second'), true);

    final secondCk =
        (await aliceAfter.client.get(after)).metadata?.appMetadata?.additional;
    expect(secondCk?['ckKid'], isNot(firstCk?['ckKid']),
        reason: 'the advertised generation moved, so a fresh content key must '
            'be cut and conveyed — reusing the old one would keep handing the '
            'superseded key to whoever still holds it');
  }, timeout: Timeout(const Duration(minutes: 2)));

  /// The reverse direction: resolving the nskey owner is direction-specific —
  /// a reader keying its ring by `sharedBy` looks up the *sender's* private —
  /// so proving one direction proves only half.
  test('bob shares with alice, and alice reads it', () async {
    final aliceSide = await nskeyClient(alice);
    final bobSide = await nskeyClient(bob);

    final keyName = uniqueKey('from_bob');
    final shared = AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = alice
      ..sharedBy = bob;

    expect(await bobSide.client.put(shared, 'bob wrote this'), true);
    await E2ESyncService.getInstance().syncData(bobSide.client.syncService);

    await E2ESyncService.getInstance().syncData(aliceSide.client.syncService);

    final received = await aliceSide.client.get(AtKey()
      ..key = keyName
      ..namespace = namespace
      ..sharedWith = alice
      ..sharedBy = bob);
    expect(received.value, 'bob wrote this',
        reason: 'the nskey owner is sharedWith on an inbound record, whichever '
            'atSign is sending');
  }, timeout: Timeout(const Duration(minutes: 2)));

  /// The pre-flight query's lifecycle rather than a static answer: an app asks
  /// before the user composes, so what matters is that the answer *changes*
  /// when the recipient enables the namespace.
  test('isReadyFor goes from false to true when bob mints', () async {
    // Top-level on purpose: a namespace *under* one bob has a key for is
    // reachable by walking up, and would correctly report ready. Only a
    // namespace with no ancestor key is genuinely unready.
    final unusedNs = 'unused${DateTime.now().microsecondsSinceEpoch}';
    final bobSide = await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);
    final runtime = CryptoRuntime(aliceSide.client);

    expect(await runtime.isReadyFor(bob, unusedNs), isFalse,
        reason: 'bob has no key at this namespace nor at any ancestor of it');

    await bobSide.ring.mintAndPublish(unusedNs);

    // A fresh sender: this arm is the cross-atSign readiness check.
    final aliceAgain = await nskeyClient(alice);
    expect(await CryptoRuntime(aliceAgain.client).isReadyFor(bob, unusedNs),
        isTrue,
        reason: 'a sender asking about a namespace bob has now published must '
            'be told yes');
  }, timeout: Timeout(const Duration(minutes: 2)));

  /// The negative alongside the per-recipient CK test: distinct keys are only
  /// meaningful if the other party genuinely cannot open the wrong one.
  test('bob cannot open the content key alice cut for herself', () async {
    final bobSide = await nskeyClient(bob);
    final aliceSide = await nskeyClient(alice);

    final selfKey = AtKey()
      ..key = uniqueKey('private_note')
      ..namespace = namespace
      ..sharedBy = alice;
    expect(await aliceSide.client.put(selfKey, 'for me alone'), true);
    await E2ESyncService.getInstance().syncData(aliceSide.client.syncService);

    final selfCk =
        (await aliceSide.client.get(selfKey)).metadata?.appMetadata?.additional;

    // Bob asks alice's atServer for the conveyance carrying her self CK. It is
    // a self key of alice's, so he is not a party to it at all.
    await expectLater(
      bobSide.client.get(AtKey()
        ..key = '${selfCk?['ckKid']}.__ck'
        ..namespace = namespace
        ..sharedBy = alice),
      throwsA(isA<AtException>()),
      reason: 'per-recipient scoping is only real if the other side fails',
    );
  }, timeout: Timeout(const Duration(minutes: 2)));

  /// The advertised key is what an attacker wants to substitute: a sender that
  /// seals to the wrong nskey hands its content key to whoever minted that key,
  /// and — because a sender never sees a decapsulation fail — nothing
  /// downstream would ever notice. So the sender verifies the advertisement's
  /// APKAM signature against the `_apsk` the signing enrollment published.
  ///
  /// It is last in the file because it leaves bob's advertisement replaced; the
  /// genuine one is republished at the end.
  test('alice refuses to seal to an advertisement that is not signed',
      () async {
    final bobSide = await nskeyClient(bob);

    // What a substitution looks like from alice's side: a well-formed
    // advertisement for a key bob never minted, carrying no signature. Written
    // straight to bob's atServer, which is where alice reads it from.
    final substituted = await XWingKeyPair.generate();
    await bobSide.client.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
      ..atKey = nskeyAdvertisementKey(bob, namespace)
      ..value = jsonEncode({
        'nskeyKid': nskeyKidOf(substituted.publicKeyBytes),
        'publicKey': base64Encode(substituted.publicKeyBytes),
      }));

    final aliceSide = await nskeyClient(alice);

    // Alice's ring survives the atSign switches this file makes, so it may
    // hold bob's GENUINE advertisement, cached well inside `advertisementTtl`.
    // Sealing to that cached key would make this row pass without ever meeting
    // the substitution it exists to detect; dropping the entry forces the
    // fetch the assertion is about.
    aliceSide.ring.forgetRemote(bob, namespace);

    await expectLater(
      aliceSide.client.put(
          AtKey()
            ..key = uniqueKey('intercepted')
            ..namespace = namespace
            ..sharedWith = bob
            ..sharedBy = alice,
          'the treaty text'),
      // Matched on the reason, not merely on AtException: `putText` rewrites
      // every AtException through AtExceptionManager, so the thrown type says
      // nothing, and a write that failed for some unrelated reason would let
      // this pass while proving nothing about the verify.
      throwsA(isA<AtClientException>().having(
          (e) => e.message, 'message', contains('carries no APKAM signature'))),
      reason: 'the write must fail rather than seal a content key to a key '
          'nobody proved bob minted',
    );

    // Put bob's genuine, signed advertisement back, so the atServer is not left
    // holding the substituted one.
    await nskeyClient(bob);
  });
}
