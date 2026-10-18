// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, RsaKeyPair, SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, EnvelopeType, SignedEnvelope, signEnvelope;
import 'package:at_client/src/crypto/nskey/mint_lock.dart' show MintLock;
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:at_commons/at_builders.dart'
    show EnrollVerbBuilder, UpdateVerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/enroll_link_fake.dart';
import 'test_utils/envelope_tamper.dart';
import 'test_utils/link_fixtures.dart';
import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';
import 'test_utils/test_keypairs.dart';

/// Per-key links: each link vouches for one key an enrollment's `_apsk`
/// lists, is written through `enroll:link`, and is checked by a walk that
/// follows keys up to the atSign's signing root.
///
/// Catalogue: docs/projects/pq/acceptance.md section 18.2.
void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMetadata;
  late List<EnrollVerbBuilder> linkCalls;
  late ({String pub, String priv}) rootPair;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
    linkCalls = [];
  });

  MockAtClient client(String enrollmentId,
          {EnrollLinkSupport enrollLink = EnrollLinkSupport.supported}) =>
      buildRemoteBackedMockClient(
          atSign: atSign,
          enrollmentId: enrollmentId,
          remoteData: remoteData,
          remoteMetadata: remoteMetadata,
          enrollLink: enrollLink,
          enrollLinkLog: linkCalls);

  AtClientSecretSharing signerOf(MockAtClient c) =>
      AtClientSecretSharing.forClient(c);

  /// Publishes a signing root for the atSign, listing its key as [status],
  /// and returns a voucher holding its private.
  Future<LinkVoucher> newRoot({String status = 'active'}) async {
    final root = await publishRoot(remoteData, atSign, status: status);
    rootPair = (pub: root.pub, priv: root.priv);
    return root.voucher;
  }

  /// A root link naming [key] of [enrollmentId] and the published root key,
  /// whose signature does not verify.
  Future<Map<String, Object?>> forgedRootLink(
      String enrollmentId, ApskSigningKey key) async {
    final link = await LinkVoucher.root(
            private: base64Decode(rootPair.priv),
            kid: publicKeyKidOfBase64(rootPair.pub))
        .sign(PqSigningChain.linkPayload(enrollmentId, key));
    return {...link, 'signature': base64Encode(Uint8List(3309))};
  }

  Future<ApskRecord> record(MockAtClient c, String enrollmentId) async =>
      (await PqSigningChain(c).readRecord(enrollmentId))!;

  /// Stores [link] for [key] on [enrollmentId]'s record through the fake
  /// atServer, bypassing every client-side policy.
  Future<void> store(MockAtClient c, String enrollmentId, ApskSigningKey key,
      Map<String, Object?> link) async {
    final current = await record(c, enrollmentId);
    await PqSigningChain(c).writeLinks(enrollmentId, {
      key.kid: (link: link, expect: current.links[key.kid]),
    });
  }

  Future<ChainResult> walk(MockAtClient c, String enrollmentId,
      {int keyIndex = 0}) async {
    final r = await record(c, enrollmentId);
    return PqSigningChain(c).walkFrom(signerOf(c), r, r.keys[keyIndex]);
  }

  group('Given a key whose link names a key of the signing root', () {
    test(
        'when the walk runs, then the link is checked against that root key '
        'and reads anchored', () async {
      final root = await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final r = await record(b, 'b-1');
      await store(b, 'b-1', r.keys.single,
          await root.sign(PqSigningChain.linkPayload('b-1', r.keys.single)));

      final result = await walk(b, 'b-1');

      expect(result.verdict, ChainVerdict.anchored, reason: result.reason);
      expect(result.path, ['b-1']);
    });

    test('when its payload carries another version, then it reads broken',
        () async {
      final root = await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final key = (await record(b, 'b-1')).keys.single;
      final payload = {...PqSigningChain.linkPayload('b-1', key), 'v': 3};
      await store(b, 'b-1', key, await root.sign(payload));

      final result = await walk(b, 'b-1');

      expect(result.verdict, ChainVerdict.broken,
          reason: 'the atServer compares the key fields only, so a link of a '
              'version this build does not read can be stored');
      expect(result.reason, contains('does not name that key'));
    });

    test(
        'when its signature fails, then it reads broken and is never tried '
        'as a chain link', () async {
      final root = await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final key = (await record(b, 'b-1')).keys.single;
      final link = await root.sign(PqSigningChain.linkPayload('b-1', key));
      await store(b, 'b-1', key, {
        ...link,
        'signature': base64Encode(Uint8List(3309)),
      });

      final result = await walk(b, 'b-1');

      expect(result.verdict, ChainVerdict.broken);
      expect(result.reason, contains('does not verify against root key'),
          reason: 'the root branch, not the chain branch, refused it');
    });

    test(
        'when a chain link names a root kid, then it reads broken, since a '
        'JWS is not checked as a root link', () async {
      await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final key = (await record(b, 'b-1')).keys.single;
      await store(
          b,
          'b-1',
          key,
          PqSigningChain.signChainLink(PqSigningChain.linkPayload('b-1', key),
              key: ApkamSigningKeys(
                  algorithm: SigningAlgoType.mldsa65,
                  publicKey: rootPair.pub,
                  privateKey: rootPair.priv),
              signerEnrollmentId: 'b-1'));

      final result = await walk(b, 'b-1');

      expect(result.verdict, ChainVerdict.broken);
      expect(result.reason, contains('is not a root link'));
    });

    test('when the link names no signer kid, then it reads broken', () async {
      final root = await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final key = (await record(b, 'b-1')).keys.single;
      final link = await root.sign(PqSigningChain.linkPayload('b-1', key))
        ..remove(PqSigningChain.rootLinkKidField);
      await store(b, 'b-1', key, link);

      final result = await walk(b, 'b-1');

      expect(result.verdict, ChainVerdict.broken);
      expect(result.reason, contains('names no signer key'));
    });

    test('when it was signed without the domain tag, then it reads broken',
        () async {
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      final pub = base64Encode(pair.publicKey);
      remoteData['public:${PqSigningRoot.recordName}$atSign'] = jsonEncode(
          apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(alg: PqSigningRoot.rootKeyAlgo, pub: pub)
      ]));
      final b = client('b-1');
      await withSigningKey(b);
      final key = (await record(b, 'b-1')).keys.single;
      final payload = PqSigningChain.linkPayload('b-1', key);
      final untagged = await MlDsa65PureDartAlgo().signBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
          secretKey: pair.secretKey);
      await store(b, 'b-1', key, {
        'v': PqSigningChain.linkVersion,
        'alg': PqSigningChain.rootLinkAlgo,
        PqSigningChain.rootLinkKidField: publicKeyKidOfBase64(pub),
        'payload': payload,
        'signature': base64Encode(untagged),
      });

      expect((await walk(b, 'b-1')).verdict, ChainVerdict.broken,
          reason: 'the root signs the domain-tagged bytes, so a signature over '
              'the bare payload is a signature over something else');
    });

    test(
        'when the record lists that root as retired, then it still reads '
        'anchored', () async {
      final root = await newRoot(status: 'retired');
      final b = client('b-1');
      await withSigningKey(b);
      final key = (await record(b, 'b-1')).keys.single;
      await store(b, 'b-1', key,
          await root.sign(PqSigningChain.linkPayload('b-1', key)));

      expect((await walk(b, 'b-1')).verdict, ChainVerdict.anchored,
          reason: 'a root link is checked long after it was signed');
    });

    test(
        'when the record lists that root under a status this build does not '
        'know, or not at all, then it reads broken', () async {
      final root = await newRoot(status: 'compromised-maybe');
      final b = client('b-1');
      await withSigningKey(b);
      final key = (await record(b, 'b-1')).keys.single;
      await store(b, 'b-1', key,
          await root.sign(PqSigningChain.linkPayload('b-1', key)));
      expect((await walk(b, 'b-1')).verdict, ChainVerdict.broken);

      await newRoot();
      expect((await walk(b, 'b-1')).verdict, ChainVerdict.broken,
          reason: 'a root the record never advertised verifies nothing');
    });
  });

  test('D1 boundary: a keyfile and a record both carrying two root entries',
      () async {
    final predecessor = await MlDsa65PureDartAlgo().generateKeyPair();
    final successor = await MlDsa65PureDartAlgo().generateKeyPair();
    final predecessorPub = base64Encode(predecessor.publicKey);
    final successorPub = base64Encode(successor.publicKey);
    void publishRoots(List<ApskSigningKey> roots) =>
        remoteData['public:${PqSigningRoot.recordName}$atSign'] =
            jsonEncode(apskAdvertisement(keys: roots));
    publishRoots([
      ApskSigningKey.forPublicKey(
          alg: PqSigningRoot.rootKeyAlgo, pub: predecessorPub)
    ]);

    final holder = client('priv-1');
    await withSigningKey(holder);
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final holderRoot = PqSigningRoot(holder, keysIo: io);
    expect(
        await holderRoot.store(atSign, predecessor.secretKey,
            public: predecessor.publicKey),
        isTrue);

    final child = client('child-1');
    await withSigningKey(child);
    final childKey = (await record(child, 'child-1')).keys.single;
    await store(
        child,
        'child-1',
        childKey,
        await LinkVoucher.root(
                private: predecessor.secretKey,
                kid: publicKeyKidOfBase64(predecessorPub))
            .sign(PqSigningChain.linkPayload('child-1', childKey)));

    publishRoots([
      ApskSigningKey.forPublicKey(
          alg: PqSigningRoot.rootKeyAlgo, pub: successorPub),
      ApskSigningKey.forPublicKey(
          alg: PqSigningRoot.rootKeyAlgo,
          pub: predecessorPub,
          status: KeyEntryStatus.retired),
    ]);
    expect(
        await holderRoot.file(
            atSign,
            Secret(
              namespace: 'buzz',
              name: PqSigningRoot.secretName,
              value: base64Encode(successor.secretKey),
            )),
        isTrue);

    final rootPrivates = (await io.read(atSign))
        .atSignKeys
        .where((m) =>
            m.role == CryptographicMaterialRole.privateSigning &&
            AtKeys.isRoleKeyId(m.keyId, PqSigningRoot.keyIdRole))
        .toList();
    expect(rootPrivates.map((m) => m.keyId).toSet(), hasLength(2),
        reason: 'the generation IS the slot: a successor files beside its '
            'predecessor, never over it');
    expect({
      for (final m in rootPrivates) m.status
    }, {
      CryptographicMaterialStatus.active,
      CryptographicMaterialStatus.retired
    }, reason: 'exactly one of them answers "what do I sign with"');

    expect(
        await PqSigningChain(holder).linkOwnKeys(signerOf(holder),
            isFullyPrivileged: () async => true, keysIo: io),
        hasLength(1));
    final holderKey = (await record(holder, 'priv-1')).keys.single;
    expect(
        (await record(holder, 'priv-1'))
            .links[holderKey.kid]![PqSigningChain.rootLinkKidField],
        publicKeyKidOfBase64(successorPub),
        reason: 'the ACTIVE root signs; a link signed with the predecessor '
            'would name a key the record lists only as retired');

    final result = await walk(child, 'child-1');
    expect(result.verdict, ChainVerdict.anchored,
        reason: 'the link signed under the root now retired still walks to '
            'the root. Reason if not: ${result.reason}');
  });

  group('Given a key whose link names a key of another enrollment', () {
    /// A anchored by a root link; B's only key chain-linked by A's key.
    Future<({MockAtClient a, MockAtClient b, ApkamSigningKeys aKey})>
        aVouchingForB() async {
      final root = await newRoot();
      final a = client('a-1');
      final aKey = await withSigningKey(a);
      final aEntry = (await record(a, 'a-1')).keys.single;
      await store(a, 'a-1', aEntry,
          await root.sign(PqSigningChain.linkPayload('a-1', aEntry)));
      final b = client('b-1');
      await withSigningKey(b);
      final bEntry = (await record(b, 'b-1')).keys.single;
      await store(
          b,
          'b-1',
          bEntry,
          PqSigningChain.signChainLink(
              PqSigningChain.linkPayload('b-1', bEntry),
              key: aKey,
              signerEnrollmentId: 'a-1'));
      return (a: a, b: b, aKey: aKey);
    }

    test(
        'when the walk runs, then it continues from that key and reads '
        'anchored through it', () async {
      final f = await aVouchingForB();

      final result = await walk(f.b, 'b-1');

      expect(result.verdict, ChainVerdict.anchored, reason: result.reason);
      expect(result.path, ['b-1', 'a-1']);
    });

    test('when the signer key carries no link, then the walk reads chained',
        () async {
      final f = await aVouchingForB();
      final aEntry = (await record(f.a, 'a-1')).keys.single;
      remoteMetadata[PqSigningChain.apskUri(atSign, 'a-1')]!.appMetadata = null;

      final result = await walk(f.b, 'b-1');

      expect(result.verdict, ChainVerdict.chained);
      expect(result.keysWalked.last, 'a-1/${aEntry.kid}');
    });

    test('when its signature does not verify, then it reads broken', () async {
      final f = await aVouchingForB();
      final bEntry = (await record(f.b, 'b-1')).keys.single;
      final found = (await record(f.b, 'b-1')).links[bEntry.kid]!;
      await store(
          f.b,
          'b-1',
          bEntry,
          SignedEnvelope.fromJson(found)
              .withEntryMember('signature', b64u('forged'))
              .toJson());

      expect((await walk(f.b, 'b-1')).verdict, ChainVerdict.broken);
    });

    test(
        'when the envelope was signed for anything else, then it reads '
        'broken', () async {
      final f = await aVouchingForB();
      final bEntry = (await record(f.b, 'b-1')).keys.single;
      await store(
          f.b,
          'b-1',
          bEntry,
          signEnvelope(PqSigningChain.linkPayload('b-1', bEntry),
                  keys: [f.aKey], type: EnvelopeType.app, enrollmentId: 'a-1')
              .toJson());

      expect((await walk(f.b, 'b-1')).verdict, ChainVerdict.broken,
          reason: 'an application signature over a payload shaped like a '
              'link is not a link');
    });

    test('when it carries two signatures, then it reads broken', () async {
      final f = await aVouchingForB();
      final mlKey = await withSigningKey(f.a, alg: SigningAlgoType.mldsa65);
      final bEntry = (await record(f.b, 'b-1')).keys.single;
      await store(
          f.b,
          'b-1',
          bEntry,
          signEnvelope(PqSigningChain.linkPayload('b-1', bEntry),
                  keys: [mlKey, f.aKey],
                  type: EnvelopeType.chainLink,
                  enrollmentId: 'a-1')
              .toJson());

      final result = await walk(f.b, 'b-1');
      expect(result.verdict, ChainVerdict.broken);
      expect(result.reason, contains('2 signatures'));
    });

    test('when its payload names another enrollment, then it reads broken',
        () async {
      final f = await aVouchingForB();
      final c = client('c-1');
      await withSigningKey(c);
      final cEntry = (await record(c, 'c-1')).keys.single;
      final bLink = (await record(f.b, 'b-1'))
          .links[(await record(f.b, 'b-1')).keys.single.kid]!;
      remoteMetadata[PqSigningChain.apskUri(atSign, 'c-1')]!.appMetadata =
          AppMetadata(providerId: 'legacy', additional: {
        PqSigningChain.linksField: {cEntry.kid: bLink}
      });

      expect((await walk(c, 'c-1')).verdict, ChainVerdict.broken,
          reason: 'a link copied onto another record names the record it was '
              'written for');
    });

    test(
        'when the signer enrollment was revoked, then it reads revoked; '
        'deleted, then deleted', () async {
      for (final (location, verdict) in [
        (EnrollmentConstants.perEnrollmentRevoked, ChainVerdict.revoked),
        (EnrollmentConstants.perEnrollmentDeleted, ChainVerdict.deleted),
      ]) {
        remoteData.clear();
        remoteMetadata.clear();
        final f = await aVouchingForB();
        final from = PqSigningChain.apskUri(atSign, 'a-1');
        remoteData['public:_apsk.a-1.$location$atSign'] =
            remoteData.remove(from)!;

        final result = await walk(f.b, 'b-1');
        expect(result.verdict, verdict, reason: result.reason);
      }
    });
  });

  group('Given two keys whose chain links each name the other as signer', () {
    test('when the walk runs from either, then it reads broken and stops',
        () async {
      final a = client('a-1');
      final aKey = await withSigningKey(a);
      final b = client('b-1');
      final bKey = await withSigningKey(b);
      final aEntry = (await record(a, 'a-1')).keys.single;
      final bEntry = (await record(b, 'b-1')).keys.single;
      await store(
          a,
          'a-1',
          aEntry,
          PqSigningChain.signChainLink(
              PqSigningChain.linkPayload('a-1', aEntry),
              key: bKey,
              signerEnrollmentId: 'b-1'));
      await store(
          b,
          'b-1',
          bEntry,
          PqSigningChain.signChainLink(
              PqSigningChain.linkPayload('b-1', bEntry),
              key: aKey,
              signerEnrollmentId: 'a-1'));

      for (final id in ['a-1', 'b-1']) {
        final result = await walk(id == 'a-1' ? a : b, id);
        expect(result.verdict, ChainVerdict.broken);
        expect(result.reason, contains('revisits'));
      }
    });

    test(
        'when a voucher would link a key its own chain passes through, then '
        'it links nothing', () async {
      final root = await newRoot();
      final a = client('a-1');
      await withSigningKey(a);
      final b = client('b-1');
      final bKey = await withSigningKey(b);
      final aEntry = (await record(a, 'a-1')).keys.single;
      final bEntry = (await record(b, 'b-1')).keys.single;
      await store(b, 'b-1', bEntry,
          await root.sign(PqSigningChain.linkPayload('b-1', bEntry)));
      await store(
          a,
          'a-1',
          aEntry,
          PqSigningChain.signChainLink(
              PqSigningChain.linkPayload('a-1', aEntry),
              key: bKey,
              signerEnrollmentId: 'b-1'));
      final aVoucher = (await PqSigningChain(a)
          .voucher(signerOf(a), isFullyPrivileged: () async => false))!;
      expect(aVoucher.keysWalked, ['a-1/${aEntry.kid}', 'b-1/${bEntry.kid}'],
          reason: 'the premise: A vouches through B');

      // NOTE: a broken link on B's key is one a chain voucher mends, so the
      // cycle rule is all that stands between A and writing a link there.
      await store(
          b,
          'b-1',
          bEntry,
          PqSigningChain.signChainLink(
              PqSigningChain.linkPayload('b-1', bEntry),
              key: bKey,
              signerEnrollmentId: 'gone-1'));
      final linked = await PqSigningChain(a).linkKeysOf(
          await record(a, 'b-1'), aVoucher,
          authenticationKey: null, verifier: signerOf(a));

      expect(linked, isEmpty);
      expect(linkCalls.where((c) => c.enrollmentId == 'b-1'), hasLength(2),
          reason: 'the two stores in this test, and nothing from A');
    });
  });

  group('Given two entries listed under one kid whose keys differ', () {
    test(
        'when the walk runs from the entry a root link does not name, then '
        'it reads broken; from the entry it names, anchored', () async {
      final root = await newRoot();
      final b = client('b-1');
      final k1 = RsaKeyPair.generate().atPublicKey.publicKey;
      final k1b = RsaKeyPair.generate().atPublicKey.publicKey;
      final kid = publicKeyKidOfBase64(k1);
      remoteData[PqSigningChain.apskUri(atSign, 'b-1')] =
          jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey(kid: kid, alg: SigningAlgoType.rsa2048, pub: k1),
        ApskSigningKey(kid: kid, alg: SigningAlgoType.rsa2048, pub: k1b),
      ]));
      remoteMetadata[PqSigningChain.apskUri(atSign, 'b-1')] = Metadata();
      final r = await record(b, 'b-1');
      expect(r.keys.map((k) => k.pub), [k1, k1b]);
      await store(b, 'b-1', r.keys.first,
          await root.sign(PqSigningChain.linkPayload('b-1', r.keys.first)));

      final fromOther = await walk(b, 'b-1', keyIndex: 1);
      final fromNamed = await walk(b, 'b-1', keyIndex: 0);

      expect(fromOther.verdict, ChainVerdict.broken);
      expect(fromOther.reason, contains('does not name that key'));
      expect(fromNamed.verdict, ChainVerdict.anchored);
    });
  });

  group('Given B with linked keys', () {
    test(
        'when B lists a new key K3, then K1 keeps its link and still walks '
        'to the root', () async {
      final root = await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final k1 = (await record(b, 'b-1')).keys.single;
      await store(
          b, 'b-1', k1, await root.sign(PqSigningChain.linkPayload('b-1', k1)));

      await withSigningKey(b, alg: SigningAlgoType.mldsa65);

      final after = await record(b, 'b-1');
      expect(after.keys, hasLength(2), reason: 'the premise: K3 is listed');
      expect(after.links.keys, [k1.kid]);
      final k1After = after.keys.singleWhere((k) => k.kid == k1.kid);
      expect(
          (await PqSigningChain(b).walkFrom(signerOf(b), after, k1After))
              .verdict,
          ChainVerdict.anchored);
    });

    test('when B retires K2, still listing it, then K2 keeps its link',
        () async {
      final root = await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      await withSigningKey(b, alg: SigningAlgoType.mldsa65);
      for (final key in (await record(b, 'b-1')).keys) {
        await store(b, 'b-1', key,
            await root.sign(PqSigningChain.linkPayload('b-1', key)));
      }
      final k2 = (await record(b, 'b-1'))
          .keys
          .singleWhere((k) => k.alg == SigningAlgoType.mldsa65);

      await (b.atKeysIo! as WrittenAtKeysIo).update(atSign.toAtsign(), (keys) {
        keys.retireSigningKeys('b-1', CryptographicMaterialAlgorithm.mlDsa65);
        return true;
      });
      await signerOf(b).publishPublicSigningKey();

      final after = await record(b, 'b-1');
      final k2After = after.keys.singleWhere((k) => k.kid == k2.kid);
      expect(k2After.offeredForNewOperations, isFalse,
          reason: 'the premise: K2 is listed as retired');
      expect(
          (await PqSigningChain(b).walkFrom(signerOf(b), after, k2After))
              .verdict,
          ChainVerdict.anchored,
          reason: 'what K2 signed still walks to the root');
    });

    test('when B republishes its _apsk, then the put carries no appMetadata',
        () async {
      final b = client('b-1');
      await withSigningKey(b);
      clearInteractions(b);

      await withSigningKey(b, alg: SigningAlgoType.mldsa65);

      final put = verify(() => b.put(captureAny(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .captured
          .cast<AtKey>()
          .singleWhere(
              (k) => k.toString() == PqSigningChain.apskUri(atSign, 'b-1'));
      expect(put.metadata.appMetadata, isNull,
          reason: 'the atServer keeps the links over every write but '
              'enroll:link, so a client sends none of its own');
    });

    test(
        'when B republishes under a new key, then the put sends no ttl and '
        'no ttr — raw literal', () async {
      final b = client('b-1');
      await withSigningKey(b);
      clearInteractions(b);
      final newKey = RsaKeyPair.generate().atPublicKey.publicKey;

      await signerOf(b).publishPublicSigningKey(value: newKey);

      final key = verify(() => b.put(captureAny(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .captured
          .cast<AtKey>()
          .singleWhere(
              (k) => k.toString() == PqSigningChain.apskUri(atSign, 'b-1'));
      final command = (await PutRequestTransformer().transform(
              Tuple<AtKey, dynamic>()
                ..one = key
                ..two = newKey,
              encryptionPrivateKey:
                  pkamKeyPairFor(atSign, 'signer').atPrivateKey.privateKey,
              requestOptions: PutRequestOptions()..shouldEncrypt = false))
          .buildCommand();
      expect(
          command.split(' ').first,
          matches(RegExp(r'^update:dataSignature:[^:]+:isEncrypted:false:'
              r'public:_apsk\.b-1\.a\.__e@alice$')),
          reason: 'a ttl, ttb, ttr or ccd would come before the signature; no '
              'ttl, or the key every verifier resolves expires, and no ttr, or '
              'a reader\'s atServer may serve its copy after a rotation');
    });
  });

  group('Given a voucher writing links', () {
    test(
        'when another voucher wrote a chain link first and this one holds '
        'the root, then it reads again and replaces it, naming that link',
        () async {
      final root = await newRoot();
      final a = client('a-1');
      final aKey = await withSigningKey(a);
      final aEntry = (await record(a, 'a-1')).keys.single;
      await store(a, 'a-1', aEntry,
          await root.sign(PqSigningChain.linkPayload('a-1', aEntry)));
      final b = client('b-1');
      await withSigningKey(b);
      final stale = await record(b, 'b-1');
      final bEntry = stale.keys.single;
      final chainLink = PqSigningChain.signChainLink(
          PqSigningChain.linkPayload('b-1', bEntry),
          key: aKey,
          signerEnrollmentId: 'a-1');
      await store(b, 'b-1', bEntry, chainLink);
      linkCalls.clear();

      final linked = await PqSigningChain(b).linkKeysOf(stale, root,
          authenticationKey: null, verifier: signerOf(b));

      expect(linked, [bEntry.kid]);
      expect(linkCalls, hasLength(2),
          reason: 'the first expected no link and was refused');
      expect(linkCalls.last.links![bEntry.kid]['expect'], chainLink);
      expect(
          (await record(b, 'b-1'))
              .links[bEntry.kid]![PqSigningChain.rootLinkKidField],
          isNotNull,
          reason: 'a root link now stands on the key');
    });

    test(
        'when another voucher wrote a sound link first and this one signs '
        'chain links, then it keeps the link it finds', () async {
      final root = await newRoot();
      final a = client('a-1');
      await withSigningKey(a);
      final aEntry = (await record(a, 'a-1')).keys.single;
      await store(a, 'a-1', aEntry,
          await root.sign(PqSigningChain.linkPayload('a-1', aEntry)));
      final b = client('b-1');
      await withSigningKey(b);
      final stale = await record(b, 'b-1');
      final bEntry = stale.keys.single;
      final first = await root.sign(PqSigningChain.linkPayload('b-1', bEntry));
      await store(b, 'b-1', bEntry, first);
      final aVoucher = (await PqSigningChain(a)
          .voucher(signerOf(a), isFullyPrivileged: () async => false))!;
      expect(aVoucher.isRoot, isFalse);
      linkCalls.clear();

      final linked = await PqSigningChain(a).linkKeysOf(stale, aVoucher,
          authenticationKey: null, verifier: signerOf(a));

      expect(linked, isEmpty);
      expect(linkCalls, hasLength(1));
      expect((await record(b, 'b-1')).links[bEntry.kid], first);
    });

    test(
        'when the target lists its authentication key, then that key takes '
        'no link', () async {
      final root = await newRoot();
      final b = client('b-1');
      await signerOf(b).publishPublicSigningKey();
      final r = await record(b, 'b-1');
      expect(r.keys.single.pub,
          pkamKeyPairFor(atSign, 'b-1').atPublicKey.publicKey,
          reason: 'the premise: B holds no client data signing key, so its '
              '_apsk is its authentication key');

      final linked = await PqSigningChain(b).linkKeysOf(r, root,
          authenticationKey:
              pkamKeyPairFor(atSign, 'b-1').atPublicKey.publicKey,
          verifier: signerOf(b));

      expect(linked, isEmpty);
      expect(linkCalls, isEmpty, reason: 'nothing to link sends nothing');
      expect((await walk(b, 'b-1')).verdict, ChainVerdict.unsigned);
    });

    test(
        'when it holds neither the root nor a key with a link, then it has '
        'no voucher, and its authentication key never is one', () async {
      final a = client('a-1');
      await signerOf(a).publishPublicSigningKey();
      expect(
          await PqSigningChain(a)
              .voucher(signerOf(a), isFullyPrivileged: () async => true),
          isNull);

      await withSigningKey(a);
      expect(
          await PqSigningChain(a)
              .voucher(signerOf(a), isFullyPrivileged: () async => true),
          isNull,
          reason: 'a client data signing key with no link vouches for nothing');
    });

    test(
        'when its own linked key no longer walks to the root, then it has no '
        'voucher', () async {
      await newRoot();
      final a = client('a-1');
      await withSigningKey(a);
      final aEntry = (await record(a, 'a-1')).keys.single;
      await store(a, 'a-1', aEntry, await forgedRootLink('a-1', aEntry));

      expect(
          await PqSigningChain(a)
              .voucher(signerOf(a), isFullyPrivileged: () async => true),
          isNull);
    });
  });

  group('Given a bare RSA client data signing key', () {
    test(
        'when a root holder links it and it then vouches for another '
        'enrollment, then both walk to the root', () async {
      final root = await newRoot();
      final b = client('b-1');
      final bKey = await withSigningKey(b);
      final value = remoteData[PqSigningChain.apskUri(atSign, 'b-1')]!;
      expect(value, bKey.publicKey,
          reason: 'the premise: published bare, not in the list form');

      final linked = await PqSigningChain(b).linkKeysOf(
          await record(b, 'b-1'), root,
          authenticationKey:
              pkamKeyPairFor(atSign, 'b-1').atPublicKey.publicKey,
          verifier: signerOf(b));
      expect(linked, [publicKeyKidOfBase64(bKey.publicKey)]);
      expect((await walk(b, 'b-1')).verdict, ChainVerdict.anchored);

      final c = client('c-1');
      await withSigningKey(c);
      final bVoucher = (await PqSigningChain(b)
          .voucher(signerOf(b), isFullyPrivileged: () async => false))!;
      await PqSigningChain(b).linkKeysOf(await record(b, 'c-1'), bVoucher,
          authenticationKey:
              pkamKeyPairFor(atSign, 'c-1').atPublicKey.publicKey,
          verifier: signerOf(b));

      final fromC = await walk(c, 'c-1');
      expect(fromC.verdict, ChainVerdict.anchored, reason: fromC.reason);
      expect(fromC.path, ['c-1', 'b-1']);
    });
  });

  group('Given a client holding the signing root\'s private key', () {
    test('when it is not fully privileged, then it signs no root link with it',
        () async {
      final a = client('a-1');
      await withSigningKey(a);
      await giveRoot(a, remoteData);

      expect(
          (await PqSigningChain(a)
                  .voucher(signerOf(a), isFullyPrivileged: () async => true))
              ?.isRoot,
          isTrue,
          reason: 'the control: fully privileged, it vouches with the root');
      expect(
          await PqSigningChain(a)
              .voucher(signerOf(a), isFullyPrivileged: () async => false),
          isNull,
          reason: 'its own key has no link, so without the root it has '
              'nothing to vouch with');
    });

    test(
        'when the atSign publishes no root and it is fully privileged, then '
        'minting one root-links its own keys through enroll:link', () async {
      final f = client('f-1');
      await withSigningKey(f);
      final remote = f.getRemoteSecondary()!;
      when(() => remote.executeVerb(any(that: isA<UpdateVerbBuilder>())))
          .thenAnswer((inv) async {
        final builder = inv.positionalArguments[0] as UpdateVerbBuilder;
        remoteData[builder.atKey.toString()] = builder.value as String;
        return 'data:1';
      });

      final minted =
          await PqSigningRoot(f, keysIo: f.atKeysIo, mintLock: _GrantedLock(f))
              .mintIfAbsent(isFullyPrivileged: true);

      expect(minted, isNotNull, reason: 'the premise: this client minted');
      final key = (await record(f, 'f-1')).keys.single;
      expect(linkCalls.single.enrollmentId, 'f-1');
      expect(linkCalls.single.links![key.kid]['link']['payload'], isA<Map>(),
          reason: 'a root link');
      expect((await walk(f, 'f-1')).verdict, ChainVerdict.anchored);
    });
  });

  group('Given B whose key K1 has a link, minting a new key K2', () {
    test(
        'when B advertises K2, then B links K2 itself through enroll:link on '
        'its own record, signed with K1, and K2 walks to the root through K1, '
        'which keeps its own link though it is retired', () async {
      final root = await newRoot();
      final b = buildRemoteBackedMockClient(
          atSign: atSign,
          enrollmentId: 'b-1',
          remoteData: remoteData,
          remoteMetadata: remoteMetadata,
          enrollLinkLog: linkCalls,
          posture: PqPosture.pqActive);
      final k1 = await withSigningKey(b);
      final k1Entry = (await record(b, 'b-1')).keys.single;
      await store(b, 'b-1', k1Entry,
          await root.sign(PqSigningChain.linkPayload('b-1', k1Entry)));
      linkCalls.clear();

      final result =
          await SigningKeyMinting(b, updater: _Republishing(remoteData, atSign))
              .reconcileSigningKeys();

      expect(result.minted, [SigningAlgoType.mldsa65]);
      expect(result.retired, [SigningAlgoType.rsa2048],
          reason: 'the premise: K1 is retired in the reconcile that mints K2');
      final after = await record(b, 'b-1');
      final k2Entry =
          after.keys.singleWhere((k) => k.alg == SigningAlgoType.mldsa65);
      expect(linkCalls.single.enrollmentId, 'b-1');
      expect(linkCalls.single.links!.keys, [k2Entry.kid]);
      final link = SignedEnvelope.fromJson(after.links[k2Entry.kid]!);
      expect(link.signature.kid, publicKeyKidOfBase64(k1.publicKey));
      expect(link.signerEnrollmentId, 'b-1');

      final walked =
          await PqSigningChain(b).walkFrom(signerOf(b), after, k2Entry);
      expect(walked.verdict, ChainVerdict.anchored, reason: walked.reason);
      expect(walked.keysWalked, ['b-1/${k2Entry.kid}', 'b-1/${k1Entry.kid}']);
      expect(after.links.keys, containsAll([k1Entry.kid, k2Entry.kid]));
    });
  });

  group('Given an enrollment with linked and unlinked keys', () {
    test(
        'when it signs content, then only the keys with a link sign, and '
        'with none linked every key signs', () async {
      final root = await newRoot();
      final b = client('b-1');
      final k1 = await withSigningKey(b);
      await withSigningKey(b, alg: SigningAlgoType.mldsa65);
      final chain = PqSigningChain(b);

      await chain.refreshOwnLinks();
      expect((await signerOf(b).wrapAndSign('x')).signatures, hasLength(2),
          reason: 'no key has a link, so it signs as it always has');

      final k1Entry = (await record(b, 'b-1'))
          .keys
          .singleWhere((k) => k.pub == k1.publicKey);
      await store(b, 'b-1', k1Entry,
          await root.sign(PqSigningChain.linkPayload('b-1', k1Entry)));
      await chain.refreshOwnLinks();
      final one = await signerOf(b).wrapAndSign('x');
      expect(one.signatures.map((s) => s.kid), [k1Entry.kid]);

      final k2Entry = (await record(b, 'b-1'))
          .keys
          .singleWhere((k) => k.pub != k1.publicKey);
      await store(b, 'b-1', k2Entry,
          await root.sign(PqSigningChain.linkPayload('b-1', k2Entry)));
      await chain.refreshOwnLinks();
      expect((await signerOf(b).wrapAndSign('x')).signatures, hasLength(2));
    });
  });

  group('Given an enrollment the approver lists', () {
    test(
        'when every active key with a link walks to the root, then it reads '
        'anchored, though a newer key has no link yet', () async {
      final root = await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final k1 = (await record(b, 'b-1')).keys.single;
      await store(
          b, 'b-1', k1, await root.sign(PqSigningChain.linkPayload('b-1', k1)));
      await withSigningKey(b, alg: SigningAlgoType.mldsa65);

      final result = await PqSigningChain(b).verifyChain(signerOf(b), 'b-1');

      expect(result.verdict, ChainVerdict.anchored, reason: result.reason);
    });

    test('when no active key has a link, then it reads unsigned', () async {
      final b = client('b-1');
      await withSigningKey(b);

      expect((await PqSigningChain(b).verifyChain(signerOf(b), 'b-1')).verdict,
          ChainVerdict.unsigned);
    });

    test(
        'when a linked key fails, then it reads that key\'s verdict, naming '
        'the key', () async {
      await newRoot();
      final b = client('b-1');
      await withSigningKey(b);
      final k1 = (await record(b, 'b-1')).keys.single;
      await store(b, 'b-1', k1, await forgedRootLink('b-1', k1));

      final result = await PqSigningChain(b).verifyChain(signerOf(b), 'b-1');

      expect(result.verdict, ChainVerdict.broken);
      expect(result.kid, k1.kid);
    });

    test(
        'when its own record was revoked, then it reads revoked; when it '
        'never published one, unsigned', () async {
      final b = client('b-1');
      await withSigningKey(b);
      final key = PqSigningChain.apskUri(atSign, 'b-1');
      remoteData['public:_apsk.b-1.${EnrollmentConstants.perEnrollmentRevoked}'
          '$atSign'] = remoteData.remove(key)!;

      expect((await PqSigningChain(b).verifyChain(signerOf(b), 'b-1')).verdict,
          ChainVerdict.revoked);
      expect(
          (await PqSigningChain(b).verifyChain(signerOf(b), 'never-1')).verdict,
          ChainVerdict.unsigned);
    });
  });

  group('Given an atServer without enroll:link', () {
    for (final support in [
      EnrollLinkSupport.unknownToGrammar,
      EnrollLinkSupport.noHandler,
    ]) {
      test(
          'when a voucher links a key and the atServer is $support, then '
          'nothing is linked and the call does not throw', () async {
        final root = await newRoot();
        final b = client('b-1', enrollLink: support);
        await withSigningKey(b);

        final linked = await PqSigningChain(b).linkKeysOf(
            await record(b, 'b-1'), root,
            authenticationKey: null, verifier: signerOf(b));

        expect(linked, isEmpty);
        expect((await walk(b, 'b-1')).verdict, ChainVerdict.unsigned);
      });
    }
  });

  test(
      'sameKey reads one key in either base64 alphabet, padded or not, as '
      'one key', () {
    final pub = RsaKeyPair.generate().atPublicKey.publicKey;
    final url = pub.replaceAll('+', '-').replaceAll('/', '_');
    expect(PqSigningChain.sameKey(pub, url.replaceAll('=', '')), isTrue);
    expect(PqSigningChain.sameKey(pub, ' $pub\n'), isTrue);
    expect(
        PqSigningChain.sameKey(
            pub, RsaKeyPair.generate().atPublicKey.publicKey),
        isFalse);
  });
}

/// Publishes what an `enroll:update` republishes, as the atServer does: the
/// record's value changes and its links stay.
class _Republishing implements EnrollmentUpdater {
  _Republishing(this.remoteData, this.atSign);

  final Map<String, String> remoteData;
  final String atSign;

  @override
  Future<AtEnrollmentResponse> update(
      EnrollmentUpdateRequest request, AtLookUp atLookUp) async {
    remoteData[PqSigningChain.apskUri(atSign, request.enrollmentId)] =
        request.apskLegacy ??
            jsonEncode(apskAdvertisement(keys: request.signingKeys!));
    return AtEnrollmentResponse(
        request.enrollmentId, EnrollmentStatus.approved);
  }
}

/// A mint lock taken at once, whose lease has a minute to run.
class _GrantedLock extends MintLock {
  _GrantedLock(super.atClient);

  @override
  Future<T?> withLock<T>(
          AtKey lockKey, Future<T> Function(ServerMutexLease lease) mint,
          {bool ownLockIsNotContention = false}) =>
      mint(ServerMutexLease(
          lockKey, DateTime.now().add(const Duration(minutes: 1))));
}
