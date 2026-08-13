import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show AtKeys, InMemoryAtKeysIo, KeyAlgorithmType;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show recordResolvedSigningAlgo;
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

/// Where a client's signing keys come from, and what answers when the keyfile
/// holds none — which is every keyfile until something files per-algorithm
/// signing material.
void main() {
  const atSign = '@alice';
  const enrollmentId = 'enroll-a';

  late MockAtClient atClient;
  late AtChops atChops;
  late TestSigner signer;

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

      expect((await signer.signingKeys).single.algorithm,
          SigningAlgoType.mldsa65);
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
}
