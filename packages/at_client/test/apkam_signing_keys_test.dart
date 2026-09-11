import 'dart:async' show FutureOr;
import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show AtKeys, InMemoryAtKeysIo, CryptographicMaterialAlgorithm;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show recordResolvedSigningAlgo;
import 'package:at_commons/at_commons.dart'
    show AtBytes, AtKey, AtKeyNotFoundException, AtValue;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

/// Hosts [ApkamSigning] against a mock client, so a test can drive the
/// mixin directly.
class TestSigner with ApkamSigning {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestSigner');

  TestSigner(this.atClient);
}

/// Hosts [ApkamSigning] and [EnvelopeSigning], with public-key caching off.
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

/// Counts keyfile reads, so a test can assert a signer read the keyfile.
class CountingKeysIo extends InMemoryAtKeysIo {
  int reads = 0;

  @override
  FutureOr<AtKeys> read(String atSign) {
    reads++;
    return super.read(atSign);
  }
}

/// Where a client's signing keys come from, and what answers when the keyfile
/// holds none.
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
  /// it. Reading an atSign this has never been given throws.
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
      final keys = await signer.signingKeys;

      expect(keys, hasLength(1));
      expect(keys.single.publicKey, pkamPublicKey());
      expect(keys.single.algorithm, SigningAlgoType.rsa2048);
      expect(await signer.publicSigningKey, pkamPublicKey());
    });

    test('the keyfile\'s APKAM keypair answers a client holding no AtChops',
        () async {
      // The mainstream client: built from a keyfile, never handed an AtChops.
      when(() => atClient.atChops).thenReturn(null);
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..apkamPublicKey = AtBytes.fromString(rsaPair.atPublicKey.publicKey)
        ..apkamPrivateKey =
            AtBytes.fromString(rsaPair.atPrivateKey.privateKey)));

      final keys = await signer.signingKeys;

      expect(keys.single.publicKey, rsaPair.atPublicKey.publicKey);
      expect(keys.single.algorithm, SigningAlgoType.rsa2048,
          reason: 'the flat fields carry no algorithm, and are rsa2048');
    });

    test('typed ML-DSA authentication material names its own algorithm',
        () async {
      when(() => atClient.atChops).thenReturn(null);
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) =>
          keys.fileApkamMaterial(
              enrollmentId: enrollmentId,
              algorithm: CryptographicMaterialAlgorithm.mlDsa65,
              publicKey: base64Encode(mlDsaPair.publicKey),
              privateKey: base64Encode(mlDsaPair.secretKey))));

      final keys = await signer.signingKeys;

      expect(keys.single.publicKey, base64Encode(mlDsaPair.publicKey));
      expect(keys.single.algorithm, SigningAlgoType.mldsa65,
          reason: 'from the material, not from a preference or a default');
    });

    test('the keyfile\'s APKAM keypair wins over an injected AtChops',
        () async {
      // The rig's AtChops holds one RSA keypair; the keyfile holds another.
      // Which public key comes back says which source answered.
      final other = AtChopsUtil.generateAtPkamKeyPair();
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..apkamPublicKey = AtBytes.fromString(other.atPublicKey.publicKey)
        ..apkamPrivateKey = AtBytes.fromString(other.atPrivateKey.privateKey)));

      expect((await signer.signingKeys).single.publicKey,
          other.atPublicKey.publicKey,
          reason: 'the keyfile is the source; the AtChops is the door for a '
              'client that has no keyfile');
    });

    test('the fallback signs under the algorithm the client resolved',
        () async {
      recordResolvedSigningAlgo(atClient, SigningAlgoType.mldsa65);

      expect(
          (await signer.signingKeys).single.algorithm, SigningAlgoType.mldsa65);
    });

    test('the keyfile\'s signing material wins over the authentication keypair',
        () async {
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
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
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) =>
          keys.fileSigningMaterial(
              enrollmentId: enrollmentId,
              algorithm: CryptographicMaterialAlgorithm.ed25519,
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
              algorithm: CryptographicMaterialAlgorithm.mlDsa65,
              publicKey: b64('b-pub'),
              privateKey: b64('b-priv'))));

      expect((await signer.signingKeys).single.publicKey, pkamPublicKey());
    });

    test('an unreadable keyfile falls back rather than throwing', () async {
      when(() => atClient.atKeysIo).thenReturn(InMemoryAtKeysIo());

      expect((await signer.signingKeys).single.publicKey, pkamPublicKey());
    });
  });

  group('signingKeys reads without waiting on anything', () {
    test('it returns while a startup step is still parked', () async {
      // NOTE: a signer must answer from the keyfile without awaiting any other
      // startup work — startup steps sign envelopes themselves, so a signer
      // that waits deadlocks every signer in the process.
      final io = CountingKeysIo();
      await io.write(atSign, AtKeys(atsign: atSign.toAtsign()));
      when(() => atClient.atKeysIo).thenReturn(io);

      final keys = await signer.signingKeys.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('a signer must not wait for any other work; '
              'waiting is what deadlocked every signer in the process'));

      expect(io.reads, greaterThan(0),
          reason: 'and it answers by READING the keyfile, not from a cache — '
              'a green here with no read would mean the fallback answered '
              'without the keyfile ever being consulted');
      expect(keys.single.publicKey, pkamPublicKey(),
          reason: 'this keyfile holds no signing material, so the '
              'authentication keypair is what may sign');
    });

    test('and it signs with the filed key once one is there', () async {
      final keyfile = AtKeys(atsign: atSign.toAtsign())
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            publicKey: b64('minted-pub'),
            privateKey: b64('minted-priv'));
      final io = CountingKeysIo();
      await io.write(atSign, keyfile);
      when(() => atClient.atKeysIo).thenReturn(io);

      final keys = await signer.signingKeys;

      expect(keys.single.publicKey, b64('minted-pub'),
          reason: 'the control for the row above: the same call, the same '
              'signer, and the only thing that changed is what the keyfile '
              'holds — so the fallback answering there is attributable');
    });
  });

  group('wrapAndSign signs with every key held', () {
    test('one signature per held key, all naming this enrollment', () async {
      final envelopeSigner = TestEnvelopeSigner(atClient);
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            publicKey: rsaPair.atPublicKey.publicKey,
            privateKey: rsaPair.atPrivateKey.privateKey)
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: base64Encode(mlDsaPair.publicKey),
            privateKey: base64Encode(mlDsaPair.secretKey))));

      final envelope = await envelopeSigner.wrapAndSign({'a': 1});

      expect(envelope.signatures, hasLength(2),
          reason: 'signing under only this build\'s strongest algorithm is '
              'unverifiable to any peer that does not implement it, which is '
              'the whole rollout problem');
      expect(envelope.signatures.map((s) => s.enid).toSet(), {enrollmentId},
          reason: 'every entry names the same signing ENROLLMENT - that is '
              'what enid is for');
      expect(envelope.signatures.map((s) => s.kid).toSet(), hasLength(2),
          reason: 'and a different KEY each, because kid names the key. This '
              'assertion read kid for the enrollment until 2026-08-31, when '
              'kid took its JOSE meaning back and the enrollment moved to '
              'enid');
      expect(envelope.signatures.map((s) => s.alg).toList(),
          ['ML-DSA-65', 'RS256'],
          reason: 'strongest first, which is the order signingKeys returns');
    });

    test('one held key is still one signature', () async {
      final envelope = await TestEnvelopeSigner(atClient).wrapAndSign({'a': 1});

      expect(envelope.signatures, hasLength(1));
      expect(envelope.signature.alg, 'RS256');
    });
  });

  group('publicSigningKeyValue', () {
    test('one rsa2048 key publishes bare, exactly as it always has', () async {
      // NOTE: an _apsk consumer that does not know the array base64-decodes
      // the value as an RSA key, so publishing JSON where a bare key would do
      // breaks it.
      final value = await signer.publicSigningKeyValue;

      expect(value, pkamPublicKey());
      expect(value.startsWith('{'), isFalse);
    });

    test('a single non-rsa2048 key publishes the array', () async {
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
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: b64('mldsa-pub'),
            privateKey: b64('mldsa-priv'))));

      final advertised = jsonDecode(await signer.publicSigningKeyValue);
      final entries = (advertised['keys'] as List).cast<Map>();

      expect(entries.map((e) => e['alg']).toList(), ['mldsa65', 'rsa2048']);
      expect(entries.map((e) => e['pub']).toList(),
          [b64('mldsa-pub'), b64('rsa-pub')]);
      expect(entries.map((e) => e['status']).toList(), [null, null]);
      expect(entries.map((e) => e['pub']), isNot(contains(pkamPublicKey())));
    });

    test('an enrollment holding its own authentication keypair publishes bare',
        () async {
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) =>
          keys.fileSigningMaterial(
              enrollmentId: enrollmentId,
              algorithm: CryptographicMaterialAlgorithm.rsa2048,
              publicKey: pkamPublicKey(),
              privateKey: b64('rsa-priv'))));

      final value = await signer.publicSigningKeyValue;

      expect(value, pkamPublicKey());
    });

    test('a retired signing key stays advertised, marked retired', () async {
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            publicKey: b64('old-rsa-pub'),
            privateKey: b64('old-rsa-priv'))
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
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
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
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
      when(() => atClient.atKeysIo).thenReturn(await keySource((keys) => keys
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))
        ..retireKey(enrollmentId, 'sign:rsa2048:1')
        ..fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            publicKey: b64('rsa-pub'),
            privateKey: b64('rsa-priv'))));

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
      final written = stubPutAndGet('a-different-key-published-earlier');

      await signer.publishPublicSigningKey();

      expect(written, [pkamPublicKey()]);
    });
  });
}
