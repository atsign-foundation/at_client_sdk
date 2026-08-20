import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show AtKeys, InMemoryAtKeysIo, KeyAlgorithmType;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show recordResolvedSigningAlgo;
import 'package:at_commons/at_commons.dart'
    show AtKey, AtKeyNotFoundException, AtValue;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

class TestSigner with ApkamSigning {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestSigner');

  TestSigner(this.atClient);
}

class TestEnvelopeSigner with ApkamSigning, EnvelopeSigning {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestEnvelopeSigner');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;

  TestEnvelopeSigner(this.atClient);
}

/// Where a client's signing keys come from, and what answers when the keyfile
/// holds none — which is every keyfile until something files per-algorithm
/// signing material.
void main() {
  const atSign = '@alice';
  const enrollmentId = 'enroll-a';

  late MockAtClient atClient;
  late AtChops atChops;
  late TestSigner signer;
  late AtPkamKeyPair rsaPair;
  late ({Uint8List publicKey, Uint8List secretKey}) mlDsaPair;

  String b64(String label) => base64Encode(utf8.encode(label));

  String pkamPublicKey() =>
      atChops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;

  /// A key source holding [atSign]'s keyfile with whatever [fill] files into
  /// it. Reading an atSign this has never been given throws, which is the
  /// unreadable-keyfile arm.
  Future<InMemoryAtKeysIo> keySource(void Function(AtKeys keys) fill) async {
    final keys = AtKeys(atsign: atSign.toAtsign());
    fill(keys);
    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    return io;
  }

  setUpAll(() async {
    registerFallbackValue(AtKey());
    rsaPair = AtChopsUtil.generateAtPkamKeyPair();
    mlDsaPair = await MlDsa65PureDartAlgo().generateKeyPair();
  });

  setUp(() {
    atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));

    atClient = MockAtClient();
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.atKeysIo).thenReturn(null);

    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookUp();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

    signer = TestSigner(atClient);
  });

  group('signingKeys', () {
    test('falls back to the APKAM authentication keypair with no key source',
        () async {
      // Not a stopgap: that key's public half stays in _apsk permanently,
      // because everything signed before an enrollment held signing keys of
      // its own was signed by it. A source-less client is a deliberate,
      // tested property, so this arm has to answer rather than throw.
      final keys = await signer.signingKeys;

      expect(keys, hasLength(1));
      expect(keys.single.publicKey, pkamPublicKey());
      expect(keys.single.algorithm, SigningAlgoType.rsa2048);
      expect(await signer.publicSigningKey, pkamPublicKey());
    });

    test('the fallback signs under the algorithm the client resolved',
        () async {
      // A retrofitted client authenticates ML-DSA, and an envelope it signs
      // RSA is refused against the _apsk its own record published.
      recordResolvedSigningAlgo(atClient, SigningAlgoType.mldsa65);

      expect(
          (await signer.signingKeys).single.algorithm, SigningAlgoType.mldsa65);
    });

    test('the keyfile\'s signing material wins over the authentication keypair',
        () async {
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.mlDsa65,
            publicKey: b64('mldsa-pub'),
            privateKey: b64('mldsa-priv'))));

      final keys = await signer.signingKeys;

      expect(keys.map((k) => k.algorithm).toList(),
          [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048],
          reason: 'strongest first, so a single-signature writer takes the '
              'strongest and a multi-signature one emits them in that order');
      expect(keys.first.publicKey, b64('mldsa-pub'));
      expect(keys.first.privateKey, b64('mldsa-priv'));
      expect(keys.map((k) => k.publicKey), isNot(contains(pkamPublicKey())),
          reason: 'the authentication keypair authenticates and nothing else '
              'once the enrollment has signing keys of its own');
      expect(await signer.publicSigningKey, b64('mldsa-pub'));
    });

    test('a held key this build cannot sign an envelope with is skipped',
        () async {
      // Ed25519 is in the strength order and in the keyfile vocabulary, and
      // no envelope signs under it — so the keyfile can hold one this build
      // must not try to use.
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) =>
          keys.fileSigningMaterial(
              enrollmentId: enrollmentId,
              algorithm: KeyAlgorithmType.ed25519,
              publicKey: b64('ed-pub'),
              privateKey: b64('ed-priv'))));

      expect((await signer.signingKeys).single.publicKey, pkamPublicKey(),
          reason: 'skipping leaves the fallback to answer; passing it on '
              'would throw out of every signer on the client');
    });

    test('another enrollment\'s signing material is not this one\'s', () async {
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) =>
          keys.fileSigningMaterial(
              enrollmentId: 'enroll-b',
              algorithm: KeyAlgorithmType.mlDsa65,
              publicKey: b64('b-pub'),
              privateKey: b64('b-priv'))));

      expect((await signer.signingKeys).single.publicKey, pkamPublicKey());
    });

    test('an unreadable keyfile falls back rather than throwing', () async {
      // The store holds no entry for this atSign, so the read throws. Signing
      // must not become impossible because a key source could not be read.
      when(() => atClient.atKeysIo).thenReturn(InMemoryAtKeysIo());

      expect((await signer.signingKeys).single.publicKey, pkamPublicKey());
    });
  });

  group('wrapAndSign signs with every key held', () {
    test('one signature per held key, all naming this enrollment', () async {
      final envelopeSigner = TestEnvelopeSigner(atClient);
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.rsa2048,
            publicKey: rsaPair.atPublicKey.publicKey,
            privateKey: rsaPair.atPrivateKey.privateKey)
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.mlDsa65,
            publicKey: base64Encode(mlDsaPair.publicKey),
            privateKey: base64Encode(mlDsaPair.secretKey))));

      final envelope = await envelopeSigner.wrapAndSign({'a': 1});

      expect(envelope.signatures, hasLength(2),
          reason: 'signing under only this build\'s strongest algorithm is '
              'unverifiable to any peer that does not implement it, which is '
              'the whole rollout problem');
      expect(envelope.signatures.map((s) => s.kid).toSet(), {enrollmentId});
      expect(envelope.signatures.map((s) => s.alg).toList(),
          ['ML-DSA-65', 'RS256'],
          reason: 'strongest first, which is the order signingKeys returns');
    });

    test('one held key is still one signature', () async {
      // The shape every client produces today, and the one that must not
      // change: nothing files per-algorithm signing material yet.
      final envelope = await TestEnvelopeSigner(atClient).wrapAndSign({'a': 1});

      expect(envelope.signatures, hasLength(1));
      expect(envelope.signature.alg, 'RS256');
    });
  });

  group('publicSigningKeyValue', () {
    test('one rsa2048 key publishes bare, exactly as it always has', () async {
      // The one form everything deployed can read. Every _apsk consumer that
      // predates the array base64-decodes the value as an RSA key, so
      // publishing JSON where a bare key would do breaks them.
      final value = await signer.publicSigningKeyValue;

      expect(value, pkamPublicKey());
      expect(value.startsWith('{'), isFalse);
    });

    test('a single non-rsa2048 key publishes the array', () async {
      // A bare value says "rsa2048" by convention, so it cannot describe this
      // key at all — nothing could read it.
      recordResolvedSigningAlgo(atClient, SigningAlgoType.mldsa65);

      final advertised = jsonDecode(await signer.publicSigningKeyValue);
      expect(advertised['v'], 1);
      expect((advertised['keys'] as List).single['alg'], 'mldsa65');
      expect((advertised['keys'] as List).single['pub'], pkamPublicKey());
    });

    test('several keys publish the array, strongest first', () async {
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.mlDsa65,
            publicKey: b64('mldsa-pub'),
            privateKey: b64('mldsa-priv'))));

      final advertised = jsonDecode(await signer.publicSigningKeyValue);
      final entries = (advertised['keys'] as List).cast<Map>();

      // The held keys, strongest first, and nothing else. The APKAM
      // authentication key is absent: this enrollment holds signing keys, so
      // that key never signed anything durable and has nothing to verify.
      expect(entries.map((e) => e['alg']).toList(), ['mldsa65', 'rsa2048']);
      expect(entries.map((e) => e['pub']).toList(),
          [b64('mldsa-pub'), b64('rsa-pub')]);
      expect(entries.map((e) => e['status']).toList(), [null, null]);
      expect(entries.map((e) => e['pub']), isNot(contains(pkamPublicKey())));
    });

    test('an enrollment holding its own authentication keypair publishes bare',
        () async {
      // Its own authentication keypair filed as signing material: one key,
      // listed once, as the active signer. One active rsa2048 entry is the
      // bare form, which is what every deployed reader parses.
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) =>
          keys.fileSigningMaterial(
              enrollmentId: enrollmentId,
              algorithm: KeyAlgorithmType.rsa2048,
              publicKey: pkamPublicKey(),
              privateKey: b64('rsa-priv'))));

      final value = await signer.publicSigningKeyValue;

      expect(value, pkamPublicKey());
    });

    test('a retired signing key stays advertised, marked retired', () async {
      // A key is retained for what it SIGNED. Withdrawing this entry would
      // retroactively unverify every envelope it produced, which is a loss no
      // later publish undoes.
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.rsa2048,
            publicKey: b64('old-rsa-pub'),
            privateKey: b64('old-rsa-priv'))
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.mlDsa65,
            publicKey: b64('mldsa-pub'),
            privateKey: b64('mldsa-priv'))
        ..retireKey(enrollmentId, 'sign:rsa2048:1')));

      final entries =
          (jsonDecode(await signer.publicSigningKeyValue)['keys'] as List)
              .cast<Map>();

      expect(entries.map((e) => e['alg']).toList(), ['mldsa65', 'rsa2048']);
      expect(entries.map((e) => e['pub']).toList(),
          [b64('mldsa-pub'), b64('old-rsa-pub')]);
      expect(entries.map((e) => e['status']).toList(), [null, 'retired']);
    });

    test('a retired signing key is advertised even with no active one',
        () async {
      // Nothing active left, so the APKAM authentication key is the signer
      // again and is advertised as such — beside, not instead of, the retired
      // entry it replaced.
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.rsa2048,
            publicKey: b64('old-rsa-pub'),
            privateKey: b64('old-rsa-priv'))
        ..retireKey(enrollmentId, 'sign:rsa2048:1')));

      final entries =
          (jsonDecode(await signer.publicSigningKeyValue)['keys'] as List)
              .cast<Map>();

      expect(entries.map((e) => e['pub']).toList(),
          [pkamPublicKey(), b64('old-rsa-pub')]);
      expect(entries.map((e) => e['status']).toList(), [null, 'retired']);
    });

    test('a retired key matching an active signer is not listed twice',
        () async {
      // One key described as both current and withdrawn is a document a
      // verifier has to choose between with nothing to choose on. Reachable
      // when a key is retired and the same material is filed again — a new
      // generation of the same public half.
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))
        ..retireKey(enrollmentId, 'sign:rsa2048:1')
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))));

      // The active generation wins, and one active rsa2048 entry is bare.
      expect(await signer.publicSigningKeyValue, b64('rsa-pub'));
    });
  });

  group('publishPublicSigningKey', () {
    /// Records what was put, so a test can tell "wrote nothing" from "wrote
    /// the same value again".
    List<String> stubPutAndGet(String? alreadyPublished) {
      final written = <String>[];
      when(() => atClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
        if (alreadyPublished == null) {
          throw AtKeyNotFoundException('not there');
        }
        return Future.value(AtValue()..value = alreadyPublished);
      });
      when(() => atClient.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((i) {
        written.add(i.positionalArguments[1] as String);
        return Future.value(true);
      });
      return written;
    }

    test('publishes when nothing is there', () async {
      final written = stubPutAndGet(null);

      await signer.publishPublicSigningKey();

      expect(written, [pkamPublicKey()]);
    });

    test('writes nothing when the published value already matches', () async {
      final written = stubPutAndGet(pkamPublicKey());

      await signer.publishPublicSigningKey();

      expect(written, isEmpty);
    });

    test('republishes when the published value is not what it holds', () async {
      // The defect this replaces: it read the record, logged "have already
      // published" and returned, so a key that had rotated never reached the
      // atServer and every envelope signed with the new one was verified
      // against the old.
      final written = stubPutAndGet('a-different-key-published-earlier');

      await signer.publishPublicSigningKey();

      expect(written, [pkamPublicKey()]);
    });
  });
}
