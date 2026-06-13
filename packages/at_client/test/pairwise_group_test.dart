import 'dart:convert' show base64Encode, utf8;
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class TestSharer
    with
        ApkamSigning,
        EnvelopeSigning,
        PairwiseClientRegistration,
        PairwiseSecretSharing {
  @override
  final AtClient atClient;
  @override
  final AtSignLogger logger = AtSignLogger('TestSharer');
  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;

  TestSharer(this.atClient);
}

void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;

  final seedA = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final seedB = Uint8List.fromList(List<int>.generate(32, (i) => 32 + i));

  setUpAll(() => registerFallbackValue(AtKey()));

  MockAtClient buildMockClient(String enrollmentId) {
    final atClient = MockAtClient();
    final atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookupImpl();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);
    when(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
      remoteData[inv.positionalArguments[0].toString()] =
          inv.positionalArguments[1];
      return Future.value(true);
    });
    AtValue lookup(inv) {
      final value = remoteData[inv.positionalArguments[0].toString()];
      if (value == null) {
        throw AtKeyNotFoundException('${inv.positionalArguments[0]} not found');
      }
      return AtValue()..value = value;
    }

    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) => Future.value(lookup(inv)));
    when(() => atClient.get(any()))
        .thenAnswer((inv) => Future.value(lookup(inv)));
    when(() => atClient.getAtKeys(
        regex: any(named: 'regex'),
        showHiddenKeys: any(named: 'showHiddenKeys'),
        useRemoteAtServer: any(named: 'useRemoteAtServer'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      return Future.value(
          remoteData.keys.where(regex.hasMatch).map(AtKey.fromString).toList());
    });
    when(() => atClient.delete(any())).thenAnswer((inv) {
      remoteData.remove(inv.positionalArguments[0].toString());
      return Future.value(true);
    });
    return atClient;
  }

  TestSharer buildSharer(String enrollmentId, String clientId, Uint8List seed) {
    final sharer = TestSharer(buildMockClient(enrollmentId));
    sharer.loadClientKeys = () async =>
        PersistedClientKeys(clientId: clientId, xWingSeed: base64Encode(seed));
    return sharer;
  }

  late TestSharer sharerA;

  setUp(() async {
    remoteData = {};
    sharerA = buildSharer('enroll-a', 'cid-a', seedA);
    await sharerA.registerClient(namespaces: ['myapp']);
  });

  PairwiseGroup groupFor(TestSharer s, {String namespace = 'myapp'}) =>
      PairwiseGroup(sharing: s, atSign: atSign, namespace: namespace);

  group('single-client seal/open/rotate/export', () {
    test('first seal mints epoch 1 and round-trips', () async {
      final g = groupFor(sharerA);
      final sealed = await g.seal(Uint8List.fromList(utf8.encode('hello')));
      expect(sealed.epoch, 1);
      expect(g.currentEpoch, 1);
      expect(utf8.decode(await g.open(sealed)), 'hello');
    });

    test(
        'rotate increments epoch; a value sealed under the old epoch still '
        'opens (kid-is-truth)', () async {
      final g = groupFor(sharerA);
      final old = await g.seal(Uint8List.fromList(utf8.encode('v1')));
      expect(old.epoch, 1);

      await g.rotate();
      expect(g.currentEpoch, 2);
      final fresh = await g.seal(Uint8List.fromList(utf8.encode('v2')));
      expect(fresh.epoch, 2);
      expect(fresh.kid, isNot(old.kid));

      // The old ciphertext carries its own (epoch, kid); its key is still in
      // the store, so it still opens.
      expect(utf8.decode(await g.open(old)), 'v1');
      expect(utf8.decode(await g.open(fresh)), 'v2');
    });

    test('export is deterministic by (label) and changes across epochs',
        () async {
      final g = groupFor(sharerA);
      await g.seal(Uint8List.fromList(utf8.encode('x'))); // mint epoch 1

      final a1 = await g.export('c2d', 32);
      final a2 = await g.export('c2d', 32);
      final b1 = await g.export('d2c', 32);
      expect(a1, hasLength(32));
      expect(a1, equals(a2)); // same label, same epoch → identical
      expect(a1, isNot(equals(b1))); // different label → different bytes

      await g.rotate();
      final a3 = await g.export('c2d', 32);
      expect(a3, isNot(equals(a1))); // new epoch key → new derived bytes
    });

    test('open throws CryptoKeyUnavailableException for an unknown key',
        () async {
      // No peers to answer, short timeout → unrecoverable.
      final g = PairwiseGroup(
          sharing: sharerA,
          atSign: atSign,
          namespace: 'myapp',
          recoverTimeout: const Duration(milliseconds: 200));
      final bogus = Sealed(
          epoch: 9,
          kid: 'deadbeefdeadbeef',
          iv: AtChopsUtil.generateRandomIV(12).ivBytes,
          ciphertext: Uint8List.fromList([1, 2, 3]));
      await expectLater(
          g.open(bogus), throwsA(isA<CryptoKeyUnavailableException>()));
    });
  });

  group('primitives', () {
    test('kidOf differs for different key bytes, stable for the same',
        () async {
      final k1 = Uint8List.fromList(List.generate(32, (i) => i));
      final k2 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      expect(PairwiseGroup.kidOf(k1), PairwiseGroup.kidOf(k1));
      expect(PairwiseGroup.kidOf(k1), isNot(PairwiseGroup.kidOf(k2)));
      expect(PairwiseGroup.kidOf(k1), hasLength(16)); // 8 bytes hex
    });

    test('hkdfSha256 is deterministic and length-correct', () {
      final ikm = Uint8List.fromList(List.generate(32, (i) => i));
      final salt = Uint8List.fromList(utf8.encode('self:@alice:myapp'));
      final info = Uint8List.fromList(utf8.encode('c2d'));
      final a = PairwiseGroup.hkdfSha256(
          ikm: ikm, salt: salt, info: info, length: 48);
      final b = PairwiseGroup.hkdfSha256(
          ikm: ikm, salt: salt, info: info, length: 48);
      expect(a, hasLength(48));
      expect(a, equals(b));
      // Different info → different output.
      final c = PairwiseGroup.hkdfSha256(
          ikm: ikm,
          salt: salt,
          info: Uint8List.fromList(utf8.encode('d2c')),
          length: 48);
      expect(c, isNot(equals(a)));
    });
  });

  group('two clients', () {
    late TestSharer sharerB;

    setUp(() async {
      sharerB = buildSharer('enroll-b', 'cid-b', seedB);
      await sharerB.registerClient(namespaces: ['myapp']);
    });

    test('rotate distributes the epoch key; the peer opens the sealed value',
        () async {
      final gA = groupFor(sharerA);
      await gA.rotate(); // shares epoch 1 to B (registered)
      final sealed = await gA.seal(Uint8List.fromList(utf8.encode('shared')));

      // B ingests the shared epoch key, then opens A's ciphertext.
      expect(await sharerB.sweepOnce(), greaterThanOrEqualTo(1));
      final gB = groupFor(sharerB);
      expect(utf8.decode(await gB.open(sealed)), 'shared');
    });

    test('concurrent rotate: both epoch keys survive and cross-open works',
        () async {
      final gA = groupFor(sharerA);
      final gB = groupFor(sharerB);

      // Establish epoch 1 on both.
      await gA.rotate();
      await sharerB.sweepOnce();

      // Concurrent epoch-2 mints (A first, then B → distinct createdAt), each
      // sealing under its OWN new key BEFORE the convergence sweep.
      await gA.rotate(); // epoch 2, kidA — shared to B
      final fromA = await gA.seal(Uint8List.fromList(utf8.encode('byA')));
      await Future.delayed(const Duration(milliseconds: 2));
      await gB.rotate(); // epoch 2, kidB — shared to A
      final fromB = await gB.seal(Uint8List.fromList(utf8.encode('byB')));

      // Distinct keys both minted at epoch 2.
      expect(fromA.epoch, 2);
      expect(fromB.epoch, 2);
      expect(fromA.kid, isNot(fromB.kid));

      // Each ingests the other's epoch-2 key + pointer.
      await sharerA.sweepOnce();
      await sharerB.sweepOnce();

      // Both distinct epoch-2 keys survived (distinct reserved names), so each
      // client opens the value the other sealed under its own key.
      expect(utf8.decode(await gB.open(fromA)), 'byA');
      expect(utf8.decode(await gA.open(fromB)), 'byB');

      // Pointer converged: B rotated last (newest createdAt wins), so a fresh
      // seal on EITHER client now uses the same converged key.
      final convergedA = await gA.seal(Uint8List.fromList(utf8.encode('z')));
      final convergedB = await gB.seal(Uint8List.fromList(utf8.encode('z')));
      expect(convergedA.kid, convergedB.kid);
      expect(gA.currentEpoch, 2);
      expect(gB.currentEpoch, 2);
    });

    test('revoked enrollment is excluded from rotation and cannot open',
        () async {
      final gA = groupFor(sharerA);
      await gA.rotate(); // epoch 1, shared to B
      await sharerB.sweepOnce();

      // Rotate excluding B's enrollment (revocation): the new key is NOT
      // shared to B.
      await gA.rotate(excludeEnrollmentIds: {'enroll-b'});
      final sealed =
          await gA.seal(Uint8List.fromList(utf8.encode('post-revoke')));
      expect(await sharerB.sweepOnce(), 0); // nothing shared to B

      // B can't open the post-revocation ciphertext: no peer will answer its
      // pull (only A holds the key and A excluded B).
      final gB = PairwiseGroup(
          sharing: sharerB,
          atSign: atSign,
          namespace: 'myapp',
          recoverTimeout: const Duration(milliseconds: 200));
      await expectLater(
          gB.open(sealed), throwsA(isA<CryptoKeyUnavailableException>()));
    });
  });
}
