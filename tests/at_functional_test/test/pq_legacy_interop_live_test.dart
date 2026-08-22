// Three CRAM activations and six cross-atSign round trips; the 30s default is
// not enough for the group, and setUpAll runs under it too.
@Timeout(Duration(minutes: 5))
library;

// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-B4.2 — a legacy peer and a PQ-native atSign interoperate, both ways
/// (project ON-1).
///
/// The row this file exists for is the interop question, and it is a question
/// about two atSigns: a pre-PQ `@alice` and a PQ-native `@bob` must be able to
/// reach each other **by default**, because legacy key material outlives the
/// atSign's own migration (`docs/projects/pq/decisions.md` 37). Toward alice,
/// bob's app takes the explicit legacy fallback to her `public:publickey`;
/// toward bob, alice's legacy app finds `public:publickey@bob` because even a
/// PQ-native activation publishes one. The only atSign that refuses is the one
/// that asked to, at activation, and it refuses loudly.
///
/// **All three atSigns are minted here.** Borrowing a demo atSign for the
/// legacy side would not do: every one of them is retrofitted, rooted or
/// nskey-minted by some other file in this pack, so "pre-PQ" would be a claim
/// about test ordering rather than about the atSign. A CRAM activation with
/// the default signing algorithm produces the genuine article, and this file
/// asserts the difference rather than assuming it.
///
/// One-shot server state: CRAM activation works once per atSign per
/// virtualenv, so these three are this file's alone (see `config.yaml`) and it
/// clears its own keyfiles before running.
void main() {
  final rootDomain =
      AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);
  final legacyPeer =
      ConfigUtil.getYaml()['atSign']['legacyPeerAtSign'] as String;
  final pqNative = ConfigUtil.getYaml()['atSign']['pqNativeAtSign'] as String;
  final pqOptOut =
      ConfigUtil.getYaml()['atSign']['pqNativeOptOutAtSign'] as String;
  const namespace = 'wavi';

  String keysFilePath(String atSign) => 'test/testData/$atSign.atKeys';

  AtClientPreference preferenceFor(String atSign) =>
      TestUtils.getPreference(atSign)
        ..rootDomain = rootDomain.rootDomain
        ..rootPort = rootDomain.rootPort
        ..namespace = namespace;

  /// A CRAM activation with the default (RSA) signing algorithm — an atSign in
  /// exactly the shape every atSign was in before this programme started.
  Future<AtClient> onboardLegacy(String atSign) async {
    final atKeysIo = FileAtKeysIo(filePath: keysFilePath);
    final response = await AtAuth.create().onboard(
        AtOnboardingRequest(atSign, rootDomain: rootDomain)
          ..atKeysIo = atKeysIo
          ..appName = 'wavi'
          ..deviceName = 'legacy'
          ..namespace = namespace,
        cramKeyMap[atSign]!);
    expect(response.isSuccessful, true,
        reason: 'the legacy peer must activate before anything can be said '
            'about reaching it');
    // Its own manager, not the singleton: the two sides of an interop test
    // have to be live at the same time, and `getInstance().setCurrentAtSign`
    // stops the outgoing client.
    final manager = await AtClientManager(atSign)
        .fromAuthSession(response.session!, preferenceFor(atSign));
    return manager.atClient;
  }

  /// `plookup` for a public record, as the value or null when the atServer has
  /// no such record. Used for both arms of the same question, so a null here
  /// means "absent" only because the identical call returns a value on the
  /// atSign that has one.
  Future<String?> plookupOrNull(AtClient client, String key) async {
    try {
      final response = await client
          .getRemoteSecondary()!
          .executeCommand('plookup:$key\n', auth: true);
      if (response == null || !response.startsWith('data:')) return null;
      final value = response.replaceFirst('data:', '').trim();
      return value.isEmpty || value == 'null' ? null : value;
    } catch (_) {
      return null;
    }
  }

  // A record another atSign has to read NOW goes straight to the atServer,
  // rather than waiting for sync to get round to it. The legacy shared-key
  // conveyance is already written remote-first for the same reason, so leaving
  // the data record local-first would put the pointer ahead of the value.
  final remoteWrite = PutRequestOptions()..useRemoteAtServer = true;
  final remoteRead = GetRequestOptions()..useRemoteAtServer = true;

  late AtClient legacyClient;
  late AtClient pqClient;

  setUpAll(() async {
    // AtAuth.onboard refuses if a keyfile already exists, and the runner
    // clears only @srie's. Without this the file passes in isolation and fails
    // in the suite on a leftover from an earlier run.
    for (final atSign in [legacyPeer, pqNative, pqOptOut]) {
      for (final path in [keysFilePath(atSign), '${keysFilePath(atSign)}.bak']) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    }

    legacyClient = await onboardLegacy(legacyPeer);
    pqClient = (await pqNativeOnboard(
      atSign: pqNative,
      cramSecret: cramKeyMap[pqNative]!,
      preference: preferenceFor(pqNative),
      atKeysIo: FileAtKeysIo(filePath: keysFilePath),
      appName: 'wavi',
      deviceName: 'pq-native',
      manager: AtClientManager(pqNative),
    ))
        .atClient;
  });

  test('the two atSigns really are a legacy one and a PQ-native one', () async {
    // The premise the rest of the file rests on. Both arms of the same
    // question, so "absent" on the legacy side means absent rather than
    // "plookup did not work here" — the identical call returns a root on the
    // PQ-native side.
    expect(await plookupOrNull(pqClient, 'pq_signing_root$pqNative'),
        contains('mldsa65'),
        reason: 'the PQ-native activation creates the atSign-level signing '
            'root');
    expect(await plookupOrNull(legacyClient, 'pq_signing_root$legacyPeer'),
        isNull,
        reason: 'a default-algorithm activation creates no signing root, so '
            'this atSign is pre-PQ in the sense the row means');

    // And the difference is in the key material too: a PQ enrollment's APKAM
    // is typed material under its enrollment id and the flat fields stay
    // empty, where a legacy one fills them.
    final legacyKeys = await FileAtKeysIo(filePath: keysFilePath).read(legacyPeer);
    expect(legacyKeys.apkamPublicKey, isNotNull,
        reason: 'a legacy activation mints an RSA APKAM into the flat fields');
    final pqKeys = await FileAtKeysIo(filePath: keysFilePath).read(pqNative);
    expect(pqKeys.apkamPublicKey, isNull,
        reason: 'a PQ activation files its ML-DSA APKAM as typed material, so '
            'a reader that cannot handle that fails loudly rather than '
            'signing with the RSA routine');
  });

  test(
      'UC-B4.2 inbound · a legacy app on @alice shares with a PQ-native @bob, '
      'and @bob reads it', () async {
    // GIVEN a pre-PQ atSign whose app has never heard of the nskey data path:
    //       a default preference, so its writes go out legacy.
    expect(legacyClient.getPreferences()!.crypto,
        same(const CryptoConfig.eraDefault()),
        reason: 'the sending app is legacy by construction — no crypto config '
            'at all, which is what every published app has today');

    // The precondition the row turns on, stated where it is used: a PQ-native
    // activation publishes public:publickey by DEFAULT, so a legacy sender has
    // something to encrypt to.
    expect(await plookupOrNull(legacyClient, 'publickey$pqNative'), isNotNull,
        reason: 'this is the record the legacy sender fetches; without it '
            'there is no inbound direction at all');

    final shared = AtKey()
      ..key = 'treaty${DateTime.now().microsecondsSinceEpoch}'
      ..namespace = namespace
      ..sharedWith = pqNative
      ..sharedBy = legacyPeer;
    const plaintext = 'the treaty text';

    expect(
        await legacyClient.put(shared, plaintext, putRequestOptions: remoteWrite),
        true);

    // Written under the legacy provider, not something else that happens to
    // work: the whole claim is that the OLD scheme still reaches a brand-new
    // atSign.
    final asWritten = await legacyClient.get(shared, getRequestOptions: remoteRead);
    final providerId = asWritten.metadata?.appMetadata?.providerId;
    expect(providerId == null || providerId == legacyCryptoProviderId, true,
        reason: 'a legacy app writes legacy; anything else here means the '
            'sender was not the legacy peer this row describes, and the read '
            'below would prove nothing');

    final received = await pqClient.get(
        AtKey()
          ..key = shared.key
          ..namespace = namespace
          ..sharedWith = pqNative
          ..sharedBy = legacyPeer,
        getRequestOptions: remoteRead);
    expect(received.value, plaintext,
        reason: 'the PQ-native atSign opens a legacy record with the RSA '
            'encryption keypair its activation minted by default — which is '
            'what decisions 37 keeps that material for');
  });

  test(
      'UC-B4.2 outbound · a PQ app on @bob reaches a legacy @alice through the '
      'explicit fallback', () async {
    // GIVEN bob's app on the post-quantum write path, with its own namespace
    //       key minted and published.
    final ring = PublishedNskeyKeyRing(pqClient);
    pqClient.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    await ring.mintAndPublish(namespace);

    // The differential arm: alice genuinely has no namespace key, so the two
    // cases below are a real refusal and a real fallback rather than the same
    // write twice.
    expect(await CryptoRuntime(pqClient).isReadyFor(legacyPeer, namespace),
        isFalse,
        reason: 'a legacy atSign has never published an nskey — if this were '
            'true the fallback below would never be reached and the test '
            'would pass without exercising anything');

    AtKey toAlice(String prefix) => AtKey()
      ..key = '$prefix${DateTime.now().microsecondsSinceEpoch}'
      ..namespace = namespace
      ..sharedWith = legacyPeer
      ..sharedBy = pqNative;

    // WHEN the app has NOT opted into the fallback: refused, by name.
    expect(pqClient.getPreferences()!.allowLegacyCryptoFallback, isFalse);
    await expectLater(
      pqClient.put(toAlice('refused'), 'the treaty text',
          putRequestOptions: remoteWrite),
      throwsA(predicate((e) =>
          e.toString().contains(legacyPeer) &&
          e.toString().contains(namespace))),
      reason: 'a post-quantum app must not silently downgrade; the refusal '
          'names the destination and the namespace so the app can say which '
          'peer is not reachable',
    );

    // WHEN the app opts in: the write proceeds, under legacy, visibly.
    pqClient.getPreferences()!.allowLegacyCryptoFallback = true;
    final shared = toAlice('memo');
    const plaintext = 'the treaty is signed';
    expect(await pqClient.put(shared, plaintext, putRequestOptions: remoteWrite),
        true);

    final asWritten = await pqClient.get(shared, getRequestOptions: remoteRead);
    expect(asWritten.metadata?.appMetadata?.providerId, legacyCryptoProviderId,
        reason: 'the downgrade is recorded on the record itself — that is what '
            'makes it visible rather than silent');

    // THEN the legacy peer reads it with nothing but the keys it was born
    // with. This is the half of the row that only two atSigns can show.
    final received = await legacyClient.get(
        AtKey()
          ..key = shared.key
          ..namespace = namespace
          ..sharedWith = legacyPeer
          ..sharedBy = pqNative,
        getRequestOptions: remoteRead);
    expect(received.value, plaintext,
        reason: 'interop toward a legacy peer works because bob still holds '
            'legacy material and alice\'s publickey is still there to '
            'encrypt to');
  });

  test('UC-B4.2 opt-out · an atSign that refused legacy material is not '
      'reachable by a legacy peer, and says so', () async {
    // GIVEN an atSign activated PQ-native with mintLegacyMaterial:false. The
    //       flag is spent at activation and cannot be taken back, which is why
    //       it needs an atSign of its own.
    final optOutClient = (await pqNativeOnboard(
      atSign: pqOptOut,
      cramSecret: cramKeyMap[pqOptOut]!,
      preference: preferenceFor(pqOptOut),
      atKeysIo: FileAtKeysIo(filePath: keysFilePath),
      appName: 'wavi',
      deviceName: 'pq-opt-out',
      mintLegacyMaterial: false,
      manager: AtClientManager(pqOptOut),
    ))
        .atClient;

    final optOutKeys = await FileAtKeysIo(filePath: keysFilePath).read(pqOptOut);
    expect(optOutKeys.defaultEncryptionPublicKey, isNull,
        reason: 'the opt-out is a decision not to mint the legacy keypair at '
            'all, not a decision to withhold it');

    // What the activation published, established by VALUE rather than by
    // presence. The ordinary PQ-native activation publishes the key from its
    // own keyfile; the opt-out publishes nothing, so whatever stands at that
    // address is not this atSign's — and it holds no encryption key at all, so
    // it never could be.
    final pqKeys = await FileAtKeysIo(filePath: keysFilePath).read(pqNative);
    expect(await plookupOrNull(optOutClient, 'publickey$pqNative'),
        pqKeys.defaultEncryptionPublicKey.toString(),
        reason: 'the positive control: an activation that minted legacy '
            'material publishes exactly the key it minted');

    // The virtualenv image ships every demo atSign with a `public:publickey`
    // already installed — provisioning state, not something any activation
    // wrote (an untouched `@denise` has one too). A genuinely new atSign has
    // no such record, so removing this one is restoring the condition under
    // test rather than shaping it. The atSign removes its own record; nothing
    // else can.
    final removed = await optOutClient
        .getRemoteSecondary()!
        .executeCommand('delete:public:publickey$pqOptOut\n', auth: true);
    expect(removed, startsWith('data:'));
    expect(await plookupOrNull(optOutClient, 'publickey$pqOptOut'), isNull,
        reason: 'an absent publickey is how this atSign tells a legacy peer it '
            'has no legacy path');

    // WHEN the legacy peer tries anyway: refused, and named. A legacy sender
    // has no post-quantum path to fall back to, so this is the end of the road
    // rather than a downgrade in the other direction.
    await expectLater(
      legacyClient.put(
          AtKey()
            ..key = 'unreachable${DateTime.now().microsecondsSinceEpoch}'
            ..namespace = namespace
            ..sharedWith = pqOptOut
            ..sharedBy = legacyPeer,
          'the treaty text',
          putRequestOptions: remoteWrite),
      throwsA(isA<AtClientException>()),
      reason: 'the refusal is loud: the legacy sender cannot find a key to '
          'encrypt to and fails, rather than writing something unreadable',
    );

    // And the cost of having asked for it, which this run is the first to
    // show: with no legacy material the atSign cannot write a PUBLIC record at
    // all, because every public write is signed with the legacy RSA encryption
    // private key. That takes out the `_apsk` anchor and the nskey
    // advertisement — the records the post-quantum path itself needs — so the
    // opt-out is not yet a usable configuration. Recorded as plan backlog
    // 14.12; asserted here so the day it is fixed, this fails and says so.
    await expectLater(
      optOutClient.put(
          AtKey()
            ..key = 'anything${DateTime.now().microsecondsSinceEpoch}'
            ..namespace = namespace
            ..sharedBy = pqOptOut
            ..metadata = (Metadata()..isPublic = true),
          'in the clear',
          putRequestOptions: remoteWrite),
      throwsA(predicate(
          (e) => e.toString().contains('Failed to sign the public data'))),
      reason: 'public writes are signed with the legacy encryption private '
          'key, so opting out of legacy material opts out of publishing',
    );
  });
}
