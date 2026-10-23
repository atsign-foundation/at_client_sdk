// The chain and the enrollment substrate are deliberately marked @experimental.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show MlDsa65KeyPair, RsaKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart'
    show PqStartupGates;
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Per-key links against an atServer that carries `enroll:link`: who may
/// write one, what the atServer checks, what keeps it over other writes, and
/// how each writer in the client puts one there.
///
/// One atSign, used by this file alone: its signing root is minted by the
/// first enrollment this file creates, which then holds the root's private
/// key for every row after it.
///
/// Catalogue: docs/projects/pq/acceptance.md section 18.2.
void main() {
  TestUtils.isolateStorage('per_key_links_live_test');
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'links$runId';
  late String atSign;
  late AtClient owner;

  /// The fully privileged enrollment that minted the root and holds it.
  late _Enrolled rootHolder;

  /// An enrollment, its client, and the keyfile the client opened on.
  Future<_Enrolled> enrol(
    String device, {
    required AtClient approver,
    Map<String, String>? namespaces,
    PqPosture posture = PqPosture.pqReady,
    Set<SigningAlgoType>? dataSigningKeyAlgorithms,
    SigningAlgoType signingAlgo = SigningAlgoType.mldsa65,
  }) async {
    final keys = InMemoryAtKeysIo();
    final pending = await Atsign(atSign).enroll(
        otp: (await approver.enrollments.otp()).value,
        app: namespace,
        device: '$device-$runId',
        namespaces: namespaces ?? {namespace: 'rw'},
        keys: keys,
        preference: TestUtils.getPreference(atSign, posture: posture),
        signingAlgo: signingAlgo);
    await approver.enrollments.approve(pending.enrollmentId);
    final client = await pending.client(
        TestUtils.getPreference(atSign,
            posture: posture,
            authenticationKeyAlgorithm: signingAlgo,
            dataSigningKeyAlgorithms: dataSigningKeyAlgorithms,
            pqStartupGates: const PqStartupGates())
          ..namespace = namespace,
        namespace: namespace,
        storage: TestUtils.storageForPrincipal(atSign, '$device-$runId'));
    addTearDown(client.stop);
    await (client as AtClientImpl).pqBootstrap?.startupComplete;
    return _Enrolled(client, pending.enrollmentId);
  }

  PqSigningChain chainOf(AtClient c) => PqSigningChain(c);

  EnvelopeSigning verifierOf(AtClient c) =>
      AtClientEnvelopeSigner(c, publicKeyCacheSettings: null);

  Future<ApskRecord> record(String enrollmentId) async =>
      (await chainOf(owner).readRecord(enrollmentId))!;

  Future<ChainResult> verdict(String enrollmentId) =>
      chainOf(owner).verifyChain(verifierOf(owner), enrollmentId);

  /// A root link for [key] of [enrollmentId], signed with the atSign's root.
  Future<Map<String, Object?>> rootLinkFor(
      String enrollmentId, ApskSigningKey key) async {
    final voucher = await chainOf(rootHolder.client).voucher(
        verifierOf(rootHolder.client),
        isFullyPrivileged: () async => true);
    expect(voucher?.isRoot, isTrue,
        reason: 'the premise: the root holder vouches with the root');
    return voucher!.sign(PqSigningChain.linkPayload(enrollmentId, key));
  }

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['perKeyLinksAtSign'] as String;
    final ownerKeys = InMemoryAtKeysIo.holding(atSign,
        AtEncryptionKeysLoader.getInstance().createAtKeysFromDemoKeys(atSign));
    await TestUtils.seedIfCredentialless(atSign, ownerKeys);
    await TestUtils.stopClientRunningAs(atSign, ownerKeys);
    // NOTE: the owner neither mints the root nor sweeps, so the root is the
    // first enrollment's to mint, at its own start.
    owner = await Atsign(atSign).open(
        keys: ownerKeys,
        preference: TestUtils.getPreference(atSign,
            posture: legacyPlusPqProviders,
            pqStartupGates: const PqStartupGates(
                anchorOwnKeys: false, sweepUnanchoredEnrollments: false))
          ..namespace = namespace,
        namespace: namespace,
        storage: TestUtils.storageFor(atSign));
    await AtClientSecretSharing.forClient(owner).register();
    expect(await PqSigningRoot.publishedPublicKey(owner, atSign), isNull,
        reason: '$atSign must publish no signing root before this file runs: '
            'nothing else in the pack may use it');

    rootHolder = await enrol('root-holder',
        approver: owner,
        namespaces: {'*': 'rw', '__manage': 'rw', namespace: 'rw'});
  });

  tearDownAll(() async => owner.stop());

  test(
      'UC-G3.22 · a fully privileged enrollment mints a missing signing root '
      'when it starts, and root-links its own keys', () async {
    expect(await PqSigningRoot.publishedPublicKey(owner, atSign), isNotNull,
        reason: 'the root holder\'s start published one');
    expect(
        await PqSigningRoot(rootHolder.client,
                keysIo: rootHolder.client.atKeysIo)
            .privateHalf(atSign),
        isNotNull,
        reason: 'and filed its private, which every root link here signs with');
    final own = await record(rootHolder.enrollmentId);
    expect(own.links, isNotEmpty);
    for (final link in own.links.values) {
      expect(link['payload'], isA<Map>(), reason: 'a root link');
    }
    final result = await verdict(rootHolder.enrollmentId);
    expect(result.verdict, ChainVerdict.anchored, reason: result.reason);
  });

  test(
      'UC-G3.5 · an approver holding the root links the key of the enrollment '
      'it approves with a root link, and it reads anchored', () async {
    final b = await enrol('b-root', approver: rootHolder.client);

    final r = await record(b.enrollmentId);
    expect(r.keys, hasLength(1));
    final link = r.links[r.keys.single.kid];
    expect(link, isNotNull, reason: 'the approval wrote it');
    expect(link!['payload'], isA<Map>(), reason: 'a root link');
    final result = await verdict(b.enrollmentId);
    expect(result.verdict, ChainVerdict.anchored, reason: result.reason);
    expect(result.path, [b.enrollmentId], reason: 'one hop to the root');
  });

  test(
      'UC-G3.5 · an approver whose own key walks to the root links with a '
      'chain link signed with that key, and the walk goes through it',
      () async {
    final approver = await enrol('b-manage',
        approver: rootHolder.client,
        namespaces: {'__manage': 'rw', namespace: 'rw'});
    final c = await enrol('c-chain', approver: approver.client);

    final r = await record(c.enrollmentId);
    final link = SignedEnvelope.fromJson(r.links[r.keys.single.kid]!);
    expect(link.signerEnrollmentId, approver.enrollmentId);
    expect((await verdict(c.enrollmentId)).verdict, ChainVerdict.anchored);
    final walked =
        await chainOf(owner).walkFrom(verifierOf(owner), r, r.keys.single);
    expect(walked.path, [c.enrollmentId, approver.enrollmentId],
        reason: walked.reason);
  });

  test(
      'UC-G3.23 · a root holder\'s sweep replaces a chain link with a root '
      'link', () async {
    final approver = await enrol('sweep-manage',
        approver: rootHolder.client,
        namespaces: {'__manage': 'rw', namespace: 'rw'});
    final c = await enrol('sweep-chain', approver: approver.client);
    Future<ChainResult> walkFromC() async {
      final r = await record(c.enrollmentId);
      return chainOf(owner).walkFrom(verifierOf(owner), r, r.keys.single);
    }

    expect((await walkFromC()).path, [c.enrollmentId, approver.enrollmentId],
        reason: 'the premise: chain-linked through the approver');

    await (rootHolder.client.enrollmentService! as EnrollmentServiceImpl)
        .sweepUnanchoredEnrollments();

    final result = await walkFromC();
    expect(result.verdict, ChainVerdict.anchored, reason: result.reason);
    expect(result.path, [c.enrollmentId],
        reason: 'a root link now, one hop from the root');
  });

  test(
      'UC-G3.14 · enroll:link admits only the target or a caller that could '
      'approve it', () async {
    final b = await enrol('gate-target', approver: rootHolder.client);
    final c = await enrol('gate-scoped', approver: rootHolder.client);
    final d = await enrol('gate-manage-only',
        approver: rootHolder.client,
        namespaces: {'__manage': 'rw', 'other$runId': 'rw'});
    final before = await record(b.enrollmentId);
    final key = before.keys.single;
    final link = await rootLinkFor(b.enrollmentId, key);

    for (final (caller, why) in [
      (c, 'does not have access to "__manage"'),
      (d, 'not authorized for namespaces'),
    ]) {
      await expectLater(
          chainOf(caller.client).writeLinks(b.enrollmentId, {
            key.kid: (link: link, expect: before.links[key.kid]),
          }),
          throwsA(isA<UnAuthorizedException>()
              .having((e) => e.message, 'message', contains(why))),
          reason: '${caller.enrollmentId} may not approve '
              '${b.enrollmentId}, so it may not link it either');
    }
    expect((await record(b.enrollmentId)).links, before.links,
        reason: 'nothing was written');

    expect(
        await chainOf(b.client).writeLinks(b.enrollmentId, {
          key.kid: (link: link, expect: before.links[key.kid]),
        }),
        [key.kid],
        reason: 'an enrollment may link its own keys, without __manage');
  });

  test('UC-G3.15 · enroll:link checks structure, and writes all or nothing',
      () async {
    final b = await enrol('struct-target', approver: rootHolder.client);
    final before = await record(b.enrollmentId);
    final key = before.keys.single;
    final good = await rootLinkFor(b.enrollmentId, key);
    final unlisted =
        ApskSigningKey(kid: 'ffffffffffffffff', alg: key.alg, pub: key.pub);
    final chain = chainOf(rootHolder.client);

    await expectLater(
        chain.writeLinks(b.enrollmentId, {
          key.kid: (link: good, expect: before.links[key.kid]),
          unlisted.kid: (
            link: await rootLinkFor(b.enrollmentId, unlisted),
            expect: null
          ),
        }),
        throwsA(predicate((e) => '$e'.contains(unlisted.kid))));
    expect((await record(b.enrollmentId)).links, before.links,
        reason: 'all or nothing: the good link was not written either');

    final other = await enrol('struct-other', approver: rootHolder.client);
    await expectLater(
        chain.writeLinks(b.enrollmentId, {
          key.kid: (
            link: await rootLinkFor(other.enrollmentId, key),
            expect: before.links[key.kid]
          ),
        }),
        throwsA(predicate((e) => '$e'.contains('does not name enrollment'))));

    await expectLater(
        chain.writeLinks(b.enrollmentId, {
          key.kid: (
            link: {...good, 'padding': 'x' * (17 * 1024)},
            expect: before.links[key.kid]
          ),
        }),
        throwsA(predicate((e) => '$e'.contains('16384'))));

    final pending = await Atsign(atSign).enroll(
        otp: (await rootHolder.client.enrollments.otp()).value,
        app: namespace,
        device: 'struct-pending-$runId',
        namespaces: {namespace: 'rw'},
        keys: InMemoryAtKeysIo(),
        preference: TestUtils.getPreference(atSign, posture: PqPosture.pqReady),
        signingAlgo: SigningAlgoType.mldsa65);
    addTearDown(() => rootHolder.client.enrollments.deny(pending.enrollmentId));
    await expectLater(
        chain.writeLinks(pending.enrollmentId, {
          key.kid: (link: good, expect: null),
        }),
        throwsA(
            predicate((e) => '$e'.contains('only an approved enrollment'))));

    final two = await enrol('struct-two',
        approver: rootHolder.client,
        dataSigningKeyAlgorithms: const {
          SigningAlgoType.rsa2048,
          SigningAlgoType.mldsa65
        });
    final pair = await record(two.enrollmentId);
    expect(pair.keys, hasLength(2), reason: 'the premise: two keys listed');
    final sent = {
      for (final k in pair.keys) k.kid: await rootLinkFor(two.enrollmentId, k),
    };
    for (final k in pair.keys) {
      expect(sent[k.kid], isNot(pair.links[k.kid]),
          reason: 'the premise: each key\'s new link differs from the one '
              'its approval left, so reading it back proves the write');
    }
    expect(
        await chain.writeLinks(two.enrollmentId, {
          for (final k in pair.keys)
            k.kid: (link: sent[k.kid]!, expect: pair.links[k.kid]),
        }),
        unorderedEquals(pair.keys.map((k) => k.kid)));
    final written = await record(two.enrollmentId);
    for (final k in pair.keys) {
      expect(written.links[k.kid], sent[k.kid],
          reason: 'one call wrote the link it carried on each key');
    }
  });

  test(
      'UC-G3.16 · a link replaces only the link its writer found, compared as '
      'JSON', () async {
    final b = await enrol('cas-target', approver: rootHolder.client);
    final before = await record(b.enrollmentId);
    final key = before.keys.single;
    final l1 = before.links[key.kid]!;
    final l2 = await rootLinkFor(b.enrollmentId, key);
    final chain = chainOf(rootHolder.client);

    await expectLater(
        chain.writeLinks(b.enrollmentId, {
          key.kid: (link: l2, expect: null),
        }),
        throwsA(predicate((e) => '$e'.contains('read it again'))));
    expect((await record(b.enrollmentId)).links[key.kid], l1);

    expect(
        await chain.writeLinks(b.enrollmentId, {
          key.kid: (link: l2, expect: l1),
        }),
        [key.kid]);
    expect((await record(b.enrollmentId)).links[key.kid], l2);
  });

  test(
      'UC-G3.17 · other writes of an _apsk keep its links, and a key no '
      'longer listed loses its link in the same write', () async {
    final b = await enrol('carry-target', approver: rootHolder.client);
    final before = await record(b.enrollmentId);
    final k1 = before.keys.single;
    final lookUp = b.client.getRemoteSecondary()!.atLookUp;
    final k3 = await MlDsa65KeyPair.generate();
    final k3Entry = ApskSigningKey.forPublicKey(
        alg: SigningAlgoType.mldsa65, pub: k3.atPublicKey.publicKey);

    await EnrollmentUpdater().update(
        EnrollmentUpdateRequest(
            enrollmentId: b.enrollmentId, signingKeys: [k1, k3Entry]),
        lookUp);
    final republished = await record(b.enrollmentId);
    expect(republished.keys, hasLength(2), reason: 'the premise: K3 listed');
    expect(republished.links[k1.kid], before.links[k1.kid],
        reason: 'an enroll:update republish keeps the link');
    final k1After = republished.keys.singleWhere((k) => k.kid == k1.kid);
    expect(
        (await chainOf(owner).walkFrom(verifierOf(owner), republished, k1After))
            .verdict,
        ChainVerdict.anchored,
        reason: 'and it still walks to the root');

    final key = AtKey.fromString(PqSigningChain.apskUri(atSign, b.enrollmentId))
      ..metadata.appMetadata = AppMetadata(
          providerId: 'legacy',
          additional: {'apskChainLink': 'stale', 'apskRootLink': 'stale'});
    await b.client.put(key, republished.value,
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
    expect((await record(b.enrollmentId)).links[k1.kid], before.links[k1.kid],
        reason: 'a put carrying the old link fields changes no link');

    await EnrollmentUpdater().update(
        EnrollmentUpdateRequest(
            enrollmentId: b.enrollmentId, signingKeys: [k3Entry]),
        lookUp);
    expect((await record(b.enrollmentId)).links, isNot(contains(k1.kid)),
        reason: 'K1 is no longer listed, so its link went in the same write');
  });

  test(
      'UC-G3.18 · an enrollment links a key it adds, using one it has already '
      'linked', () async {
    final b = await enrol('mint-target',
        approver: rootHolder.client,
        dataSigningKeyAlgorithms: const {
          SigningAlgoType.rsa2048,
          SigningAlgoType.mldsa65
        });

    final r = await record(b.enrollmentId);
    expect(r.keys, hasLength(2),
        reason: 'the premise: its start minted an ML-DSA-65 key beside the '
            'RSA one it enrolled with');
    final k1 = r.keys.singleWhere((k) => k.alg == SigningAlgoType.rsa2048);
    final k2 = r.keys.singleWhere((k) => k.alg == SigningAlgoType.mldsa65);
    final link = SignedEnvelope.fromJson(r.links[k2.kid]!);
    expect(link.signerEnrollmentId, b.enrollmentId);
    expect(link.signature.kid, k1.kid, reason: 'signed with K1');
    final walked = await chainOf(owner).walkFrom(verifierOf(owner), r, k2);
    expect(walked.verdict, ChainVerdict.anchored, reason: walked.reason);
  });

  test(
      'UC-G3.21 · an authentication key takes no link, and an approver with '
      'no linked key writes none', () async {
    final legacy = await enrol('auth-only',
        approver: rootHolder.client,
        namespaces: {'__manage': 'rw', namespace: 'rw'},
        posture: legacyPlusPqProviders,
        signingAlgo: SigningAlgoType.rsa2048);
    final r = await record(legacy.enrollmentId);
    expect(r.links, isEmpty,
        reason: 'its _apsk is its authentication key, so its approver wrote '
            'nothing');
    await expectLater(
        chainOf(rootHolder.client).writeLinks(legacy.enrollmentId, {
          r.keys.single.kid: (
            link: await rootLinkFor(legacy.enrollmentId, r.keys.single),
            expect: null
          ),
        }),
        throwsA(predicate((e) => '$e'.contains('authentication key'))),
        reason: 'and the atServer refuses one asked for');
    expect((await verdict(legacy.enrollmentId)).verdict, ChainVerdict.unsigned);

    final g = await enrol('auth-only-approves', approver: legacy.client);
    expect((await record(g.enrollmentId)).links, isEmpty,
        reason: 'an approver holding neither the root nor a linked key links '
            'nothing');
    expect((await verdict(g.enrollmentId)).verdict, ChainVerdict.unsigned);
  });

  test(
      'UC-G3.29 · an enroll:update cannot make a client data signing key the '
      'authentication key, and installs one listed alone with no link',
      () async {
    final b = await enrol('rotate-onto-signing', approver: rootHolder.client);
    final signing = (await b.client.atKeysIo!.read(atSign))
        .signingKeysFor(b.enrollmentId)
        .single;
    final before = await record(b.enrollmentId);
    expect(before.links, contains(publicKeyKidOfBase64(signing.publicKey)),
        reason: 'the premise: the key is listed and carries a link');

    await expectLater(
        EnrollmentUpdater().update(
            EnrollmentUpdateRequest(
                enrollmentId: b.enrollmentId,
                apkamPublicKey: signing.publicKey,
                apkamPrivateKey: signing.privateKey,
                signingAlgo: SigningAlgoType.rsa2048),
            b.client.getRemoteSecondary()!.atLookUp),
        throwsA(predicate((e) =>
            '$e'.contains('AT0022') &&
            '$e'.contains('authentication key') &&
            '$e'.contains(publicKeyKidOfBase64(signing.publicKey)))),
        reason: 'refused, naming the key');
    final after = await record(b.enrollmentId);
    expect(after.value, before.value, reason: 'nothing was written');
    expect(after.links, before.links);

    final alone = await enrol('rotate-alone',
        approver: rootHolder.client,
        posture: legacyPlusPqProviders,
        signingAlgo: SigningAlgoType.rsa2048);
    final fresh = RsaKeyPair.generate();
    final response = await EnrollmentUpdater().update(
        EnrollmentUpdateRequest(
            enrollmentId: alone.enrollmentId,
            apkamPublicKey: fresh.atPublicKey.publicKey,
            apkamPrivateKey: fresh.atPrivateKey.privateKey,
            signingAlgo: SigningAlgoType.rsa2048,
            apskLegacy: fresh.atPublicKey.publicKey),
        alone.client.getRemoteSecondary()!.atLookUp);
    expect(response.enrollmentId, alone.enrollmentId);
    expect(
        (await record(alone.enrollmentId)).value, fresh.atPublicKey.publicKey,
        reason: 'a key listed alone with no link may be the authentication '
            'key, as for an enrollment holding no client data signing key');
  });

  test('UC-G3.26 · an approval conveys no link in an envelope', () async {
    final b = await enrol('no-envelope', approver: rootHolder.client);
    final sharing = AtClientSecretSharing.forClient(b.client);
    await sharing.sweepOnce(fromRemote: true);

    final names = sharing.secretStore.listSecrets().map((s) => s.name);
    expect(names, contains(enrollmentApkamSymmetricKeySecretName),
        reason: 'the premise: the approval conveyed what it conveys');
    expect(
        names.where(
            (n) => n.contains('apskChainLink') || n.contains('apskRootLink')),
        isEmpty);
    expect((await record(b.enrollmentId)).links, isNotEmpty,
        reason: 'the link is on the record instead');
  });
}

/// An enrollment this file created, and the client it runs as.
class _Enrolled {
  _Enrolled(this.client, this.enrollmentId);

  final AtClient client;
  final String enrollmentId;
}
