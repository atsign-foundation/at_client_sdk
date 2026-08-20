import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
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
      NskeyProvider(keyRing: ring, cache: ContentKeyCache(), keyAlgo: keyAlgo),
      ring
    );
  }

  group('a conveyance is written under the KEM the destination advertises', () {
    test('ML-KEM-1024 conveys under its own provider id at ver 0x03', () async {
      final (provider, _) = await providerFor(SecretSharingAlgos.mlKem1024);
      final ck =
          ContentKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));
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

    test('and refuses an owner that only opens the retired construction',
        () async {
      // The arm that makes the one above safe. Same key, same KEM — the only
      // difference is what the advertisement says it can open, which is what a
      // `suites` list exists to carry. Without this the version could only be
      // raised by upgrading every reader first.
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      final ring = _FixedRing(
          NskeyAdvertisement.single(
            publicKey: pair.publicKey,
            alg: SecretSharingAlgos.xWing,
            suites: const ['x-wing-hpke-v1'],
          ),
          pair.secretKey);
      final provider = NskeyProvider(
          keyRing: ring,
          cache: ContentKeyCache(),
          keyAlgo: SecretSharingAlgos.xWing);
      final ck = ContentKey(Uint8List(32));
      final atKey = conveyanceKey();

      // This arm used to assert the conveyance went out at `0x01`. That
      // version is retired, so the two now share no construction at all, and
      // the contract for that is a refusal: an owner sent a construction it
      // never claimed would fail on ITS side as an AEAD error naming nothing.
      await expectLater(provider.encrypt(context, atKey, ck.toBase64()),
          throwsA(isA<AtEncryptionException>()));
    });

    test('no shared construction is a refusal, not a guess', () async {
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      final ring = _FixedRing(
          NskeyAdvertisement.single(
            publicKey: pair.publicKey,
            alg: SecretSharingAlgos.xWing,
            suites: const ['x-wing-hpke-v99'],
          ),
          pair.secretKey);
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
        final ck = ContentKey(
            Uint8List.fromList(List<int>.generate(32, (i) => i * 3)));
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
          wrongProvider.encrypt(
              context, conveyanceKey(), ContentKey(Uint8List(32)).toBase64()),
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

    test('every algorithm with a KEM also states a key length', () {
      // kemFor and publicKeyLengthFor are two switches over the same ids, and
      // the advertisement reader needs both: it refuses an algorithm with no
      // KEM, then refuses a key that is not that algorithm's length. If only
      // the second gained an id the reader would accept any length for it, so
      // this pins the pair rather than either alone.
      for (final keyAlgo in SecretSharingAlgos.keyAlgos) {
        expect(SecretSharingAlgos.kemFor(keyAlgo), isNotNull,
            reason: '$keyAlgo is offered but has no KEM');
        expect(SecretSharingAlgos.publicKeyLengthFor(keyAlgo), isNotNull,
            reason: '$keyAlgo has a KEM but no key length, so a forged '
                'advertisement naming it would pass the length check');
      }
    });

    test('an unimplemented algorithm states no key length either', () {
      expect(SecretSharingAlgos.publicKeyLengthFor('kyber-1024-v9'), isNull);
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
      final providers = config.providers.whereType<NskeyProvider>().toList();

      expect(providers, hasLength(2));
      expect(providers.first.cache, same(providers.last.cache));
      expect(config.contentKeyCache, same(providers.first.cache));
    });
  });

  group('the one suite negotiation', () {
    // It was written twice — once for key packages, once for nskey — and a
    // negotiation that disagrees with itself picks different constructions for
    // the same two parties depending on which substrate is asking.

    test('the SENDER\'s order decides, not the recipient\'s', () {
      // The property a reimplementation gets wrong. Both lists contain both
      // suites, in opposite orders, so a walk driven by the wrong side
      // returns the other answer — the arms cannot collapse into each other.
      const sender = ['x-wing-rfc9180-v1', 'x-wing-hpke-v1'];
      const recipient = ['x-wing-hpke-v1', 'x-wing-rfc9180-v1'];

      expect(SecretSharingAlgos.bestSuiteBetween(sender, recipient),
          'x-wing-rfc9180-v1');
      expect(SecretSharingAlgos.bestSuiteBetween(recipient, sender),
          'x-wing-hpke-v1',
          reason: 'swapping the arguments swaps the answer, which is what '
              'proves the sender side is the preference order');
    });

    test('no shared suite is null, never a guess', () {
      expect(
          SecretSharingAlgos.bestSuiteBetween(
              ['x-wing-rfc9180-v1'], ['ml-kem-1024-rfc9180-v1']),
          isNull,
          reason: 'sealing under a construction the recipient never claimed '
              'fails on their side, as an AEAD error naming neither party');
      expect(
          SecretSharingAlgos.bestSuiteBetween(['x-wing-hpke-v1'], []), isNull);
    });

    test('a suite this build has never heard of is still negotiable', () {
      // The list is the OTHER party's statement about itself, so an entry we
      // do not recognise is not ours to filter out — only ours to not offer.
      expect(
          SecretSharingAlgos.bestSuiteBetween(
              ['from-2032', 'x-wing-hpke-v1'], ['from-2032']),
          'from-2032');
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
  Future<NskeyDecapsulationKey?> privateHalf(
          String owner, String namespace, String nskeyKid) async =>
      nskeyKid == _advertised.nskeyKid
          ? NskeyDecapsulationKey(_secretKey)
          : null;
}
