import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart' show AtEncryptionException;
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The nskey conveyance path under both key-establishment algorithms.
///
/// Everything else in the nskey suite runs on the hybrid, which is the
/// default, so without this the ML-KEM arm would be entirely unexercised — the
/// collapsed-arm case where a whole option is "supported" and never once run.
void main() {
  const owner = '@alice';
  const namespace = 'myapp';

  late MockAtClient atClient;
  late CryptoContext context;

  setUp(() {
    atClient = MockAtClient();
    context = CryptoContext(atClient: atClient);
  });

  AtKey conveyanceKey() => AtKey()
    ..key = 'ckkid.__ck'
    ..namespace = namespace
    ..sharedBy = owner;

  /// Seeds a ring with a freshly minted [keyAlgo] generation and returns the
  /// provider that conveys under it.
  Future<(NskeyProvider, InMemoryNskeyKeyRing)> providerFor(
      String keyAlgo) async {
    final kem = SecretSharingAlgos.kemFor(keyAlgo)!;
    final pair = await kem.keyPairFromSeed(kem.newSeed());
    final ring = InMemoryNskeyKeyRing()
      ..seedKeypair(owner, namespace,
          publicKey: pair.publicKey,
          privateKey: pair.secretKey,
          keyAlgo: keyAlgo);
    return (
      NskeyProvider(
          keyRing: ring, cache: ContentKeyCache(), keyAlgo: keyAlgo),
      ring
    );
  }

  group('a conveyance is written under the KEM the destination advertises', () {
    test('ML-KEM-1024 conveys under its own provider id at ver 0x03', () async {
      final (provider, _) = await providerFor(SecretSharingAlgos.mlKem1024);
      final ck = ContentKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));
      final atKey = conveyanceKey();

      final wire = await provider.encrypt(context, atKey, ck.toBase64());

      expect(provider.id, mlKemNskeyCryptoProviderId);
      expect(atKey.metadata.appMetadata?.providerId, mlKemNskeyCryptoProviderId,
          reason: 'the record carries the id that routes it back to the '
              'provider holding the right KEM');
      expect(base64Decode(wire).first, 0x03);
    });

    test('the hybrid negotiates RFC 9180 with an owner that advertises it',
        () async {
      final (provider, _) = await providerFor(SecretSharingAlgos.xWing);
      final ck =
          ContentKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));
      final atKey = conveyanceKey();

      final wire = await provider.encrypt(context, atKey, ck.toBase64());

      expect(provider.id, nskeyCryptoProviderId);
      expect(atKey.metadata.appMetadata?.providerId, nskeyCryptoProviderId);
      expect(base64Decode(wire).first, 0x02);
    });

    test('and falls back for an owner whose advertisement predates suites',
        () async {
      // The arm that makes the one above safe. Same key, same KEM — the only
      // difference is what the advertisement says it can open, which is what a
      // `suites` list exists to carry. Without this the version could only be
      // raised by upgrading every reader first.
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      final ring = _FixedRing((
        nskeyKid: nskeyKidOf(pair.publicKey),
        publicKey: pair.publicKey,
        alg: SecretSharingAlgos.xWing,
        suites: legacyNskeySuites,
      ), pair.secretKey);
      final provider = NskeyProvider(
          keyRing: ring,
          cache: ContentKeyCache(),
          keyAlgo: SecretSharingAlgos.xWing);
      final ck = ContentKey(Uint8List(32));
      final atKey = conveyanceKey();

      final wire = await provider.encrypt(context, atKey, ck.toBase64());

      expect(base64Decode(wire).first, 0x01,
          reason: 'an owner that never claimed RFC 9180 must not be sent it — '
              'the conveyance would be unopenable and nothing would say why');
      expect(await provider.decrypt(context, atKey, wire), ck.toBase64());
    });

    test('no shared construction is a refusal, not a guess', () async {
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      final ring = _FixedRing((
        nskeyKid: nskeyKidOf(pair.publicKey),
        publicKey: pair.publicKey,
        alg: SecretSharingAlgos.xWing,
        suites: const ['x-wing-hpke-v99'],
      ), pair.secretKey);
      final provider = NskeyProvider(
          keyRing: ring,
          cache: ContentKeyCache(),
          keyAlgo: SecretSharingAlgos.xWing);

      await expectLater(
          provider.encrypt(
              context, conveyanceKey(), ContentKey(Uint8List(32)).toBase64()),
          throwsA(isA<AtEncryptionException>()));
    });

    for (final keyAlgo in SecretSharingAlgos.keyAlgos) {
      test('$keyAlgo round-trips the content key', () async {
        final (provider, _) = await providerFor(keyAlgo);
        final ck =
            ContentKey(Uint8List.fromList(List<int>.generate(32, (i) => i * 3)));
        final atKey = conveyanceKey();

        final wire = await provider.encrypt(context, atKey, ck.toBase64());
        expect(await provider.decrypt(context, atKey, wire), ck.toBase64());
      });
    }

    test('a provider will not seal to the other KEM\'s advertisement',
        () async {
      // Routing sends each conveyance to the provider matching the advertised
      // algorithm. If one is addressed directly to the wrong provider it must
      // refuse: encapsulating an ML-KEM key under X-Wing produces a record
      // whose owner can never open it, and nothing downstream would say so.
      final (_, mlKemRing) = await providerFor(SecretSharingAlgos.mlKem1024);
      final wrongProvider = NskeyProvider(
          keyRing: mlKemRing,
          cache: ContentKeyCache(),
          keyAlgo: SecretSharingAlgos.xWing);

      await expectLater(
          wrongProvider.encrypt(context, conveyanceKey(),
              ContentKey(Uint8List(32)).toBase64()),
          throwsA(isA<AtEncryptionException>()));
    });
  });

  group('the provider id maps both ways', () {
    test('every offered algorithm has a conveyance provider', () {
      for (final keyAlgo in SecretSharingAlgos.keyAlgos) {
        expect(nskeyProviderIdFor(keyAlgo), isNotNull,
            reason: '$keyAlgo is offered but nothing can convey a CK to it');
      }
    });

    test('the two ids are distinct, so reads route apart', () {
      expect(nskeyProviderIdFor(SecretSharingAlgos.xWing),
          isNot(nskeyProviderIdFor(SecretSharingAlgos.mlKem1024)));
    });

    test('an unimplemented algorithm has no id rather than a default', () {
      expect(nskeyProviderIdFor('kyber-1024-v9'), isNull);
    });
  });

  group('the crypto config registers a conveyance provider per KEM', () {
    test('both ids resolve on every client', () {
      // Registered regardless of what this atSign mints: a *recipient's* KEM
      // is the recipient's choice, and a sender must be able to convey to
      // either.
      final config = CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());

      expect(config.lookup(nskeyCryptoProviderId), isNotNull);
      expect(config.lookup(mlKemNskeyCryptoProviderId), isNotNull);
    });

    test('both share one content-key cache', () {
      // The coupling CryptoConfig.nskey exists to enforce — two caches would
      // let a conveyance cache a CK the data provider then cannot find.
      final config = CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());
      final providers =
          config.providers.whereType<NskeyProvider>().toList();

      expect(providers, hasLength(2));
      expect(providers.first.cache, same(providers.last.cache));
      expect(config.contentKeyCache, same(providers.first.cache));
    });
  });
}

/// A ring serving one fixed advertisement, so a test can state exactly what an
/// owner claims — including shapes `InMemoryNskeyKeyRing` derives rather than
/// accepts, such as an advertisement written before `suites` existed.
class _FixedRing implements NskeyKeyRing {
  final NskeyAdvertisement _advertised;
  final Uint8List _secretKey;

  _FixedRing(this._advertised, this._secretKey);

  @override
  Future<NskeyAdvertisement?> currentPublic(
          String owner, String namespace) async =>
      _advertised;

  @override
  Future<Uint8List?> privateHalf(
          String owner, String namespace, String nskeyKid) async =>
      nskeyKid == _advertised.nskeyKid ? _secretKey : null;
}
