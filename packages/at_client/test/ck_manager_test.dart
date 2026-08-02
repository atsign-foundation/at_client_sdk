import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The CK manager — the step that makes `put` work at all on the nskey path.
///
/// Content keys are scoped per recipient, so "no current CK" is not a one-off
/// bootstrap: it fires on the first write to every new destination, and again
/// whenever that destination rotates. Minting one means *writing a conveyance
/// record*, which is why this runs before the write pipeline rather than inside
/// `encrypt`.
void main() {
  const owner = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  late XWingKeyPair aliceNskey;
  late XWingKeyPair bobNskey;

  setUpAll(() async {
    aliceNskey = await XWingKeyPair.generate();
    bobNskey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  /// A client whose `put` routes through the real providers, the way the put
  /// pipeline does: the conveyance record is encrypted by `at/nskey`, which
  /// seals the CK and marks it current.
  ({
    CkManager manager,
    CryptoContext context,
    InMemoryNskeyKeyRing ring,
    ContentKeyCache cache,
    List<AtKey> written,
    List<String?> providerIds,
  }) client() {
    final cache = ContentKeyCache();
    final ring = InMemoryNskeyKeyRing();
    final nskey = NskeyProvider(keyRing: ring, cache: cache);
    final manager = CkManager(cache: cache, keyRing: ring);
    final written = <AtKey>[];
    final providerIds = <String?>[];

    final mockAtClient = MockAtClient();
    when(() => mockAtClient.getCurrentAtSign()).thenReturn(owner);
    final context = CryptoContext(atClient: mockAtClient);

    when(() => mockAtClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final value = inv.positionalArguments[1] as String;
      final options =
          inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
      written.add(key);
      providerIds.add(options?.cryptoProviderId);
      await nskey.encrypt(context, key, value);
      return true;
    });

    return (
      manager: manager,
      context: context,
      ring: ring,
      cache: cache,
      written: written,
      providerIds: providerIds,
    );
  }

  AtKey selfValue(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = owner
    ..metadata = Metadata();

  AtKey sharedValue(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = owner
    ..sharedWith = bob
    ..metadata = Metadata();

  group('ensureCurrent', () {
    test('mints and conveys a CK when the destination has none', () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));

      expect(c.written, hasLength(1));
      expect(c.written.single.key, endsWith('.__ck'));
      expect(c.written.single.namespace, namespace);
      expect(c.providerIds.single, nskeyCryptoProviderId,
          reason: 'the conveyance must be routed to at/nskey explicitly, not '
              'left to the preference default');
      expect(c.cache.current(owner, namespace), isNotNull,
          reason: 'the data provider reads exactly this on the next step');
    });

    test(
        'does nothing when the current CK already matches the advertised '
        'generation', () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      await c.manager.ensureCurrent(c.context, selfValue('other'));

      expect(c.written, hasLength(1),
          reason: 'a CK is long-lived per destination — it is not re-cut per '
              'write, only when there is none or the generation moved');
    });

    test('cuts a fresh CK when the destination has rotated its nskey',
        () async {
      final c = client();
      final firstGen = c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      expect(c.cache.currentNskeyKid(owner, namespace), firstGen);

      // Rotation: a new keypair becomes the advertised generation.
      final rotated = await XWingKeyPair.generate();
      final secondGen = c.ring.seedKeypair(owner, namespace,
          publicKey: rotated.publicKeyBytes,
          privateKey: rotated.privateKeyBytes);
      expect(secondGen, isNot(firstGen));

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));

      expect(c.written, hasLength(2),
          reason: 'sealing to a superseded generation is what a revoked '
              'enrollment can still open — the re-check is the whole point');
      expect(c.cache.currentNskeyKid(owner, namespace), secondGen);
    });

    test('scopes the CK to the recipient, not the sender', () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      c.ring.seedPublicOnly(bob, namespace, publicKey: bobNskey.publicKeyBytes);

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      await c.manager.ensureCurrent(c.context, sharedValue('treaty'));

      expect(c.written, hasLength(2),
          reason: 'alice-to-self and alice-to-bob are different destinations, '
              'so they get different content keys');
      expect(c.cache.current(owner, namespace)!.ckKid,
          isNot(c.cache.current(bob, namespace)!.ckKid));

      // The conveyance for bob is addressed to bob but owned by alice.
      final toBob = c.written.last;
      expect(toBob.sharedWith, bob);
      expect(toBob.sharedBy, owner);
    });

    test('stays out of the way when the destination has no nskey at all',
        () async {
      final c = client();
      // No seeding: @bob has never used this namespace. That is the cold-start
      // case, which belongs to the at/nskey provider, not here.
      await c.manager.ensureCurrent(c.context, sharedValue('treaty'));
      expect(c.written, isEmpty);
    });
  });

  group('termination', () {
    test('the conveyance write does not itself need preparing', () {
      // This is what stops ensureCurrent recursing: it issues a put routed to
      // at/nskey, and at/nskey is not a PreparesWrites, so the pre-pass on that
      // nested write is a no-op.
      final cache = ContentKeyCache();
      final nskey =
          NskeyProvider(keyRing: InMemoryNskeyKeyRing(), cache: cache);

      expect(nskey, isNot(isA<PreparesWrites>()),
          reason: 'if at/nskey ever needed preparing, minting a CK would '
              'recurse without bound');
      expect(SymmetricAesGcmProvider(cache: cache), isA<PreparesWrites>(),
          reason: 'the data provider is the one that needs a CK in place');
    });

    test('CryptoRuntime.prepareForPut skips a provider that does not prepare',
        () async {
      final cache = ContentKeyCache();
      final mockAtClient = MockAtClient();
      when(() => mockAtClient.getCurrentAtSign()).thenReturn(owner);
      mockAtClient.getPreferences().crypto = CryptoConfig(
        defaultProviderId: nskeyCryptoProviderId,
        providers: [
          NskeyProvider(keyRing: InMemoryNskeyKeyRing(), cache: cache),
        ],
      );

      // No put is stubbed, so anything that tried to write would throw.
      await CryptoRuntime(mockAtClient)
          .prepareForPut(selfValue('treaty'), nskeyCryptoProviderId);
    });

    test('prepareForPut is a no-op for an unregistered provider id', () async {
      final mockAtClient = MockAtClient();
      when(() => mockAtClient.getCurrentAtSign()).thenReturn(owner);
      await CryptoRuntime(mockAtClient)
          .prepareForPut(selfValue('treaty'), 'at/not-registered');
    });
  });

  group('CryptoConfig.nskey', () {
    /// A client wired the way an app would wire it: one line of config, and the
    /// SDK owns the assembly.
    ({MockAtClient client, List<AtKey> written}) configured(
        InMemoryNskeyKeyRing ring) {
      final mockAtClient = MockAtClient();
      when(() => mockAtClient.getCurrentAtSign()).thenReturn(owner);
      final config = CryptoConfig.nskey(keyRing: ring);
      mockAtClient.getPreferences().crypto = config;

      final written = <AtKey>[];
      when(() => mockAtClient.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((inv) async {
        final key = inv.positionalArguments[0] as AtKey;
        final options =
            inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
        written.add(key);
        // Mirror the pipeline: route the conveyance through the runtime, which
        // resolves at/nskey out of the very config under test.
        await CryptoRuntime(mockAtClient).encryptForPut(
            key
              ..metadata.appMetadata =
                  AppMetadata(providerId: options!.cryptoProviderId!),
            inv.positionalArguments[1]);
        return true;
      });
      return (client: mockAtClient, written: written);
    }

    test('defaults writes to the data provider and registers both', () {
      final config = CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());
      expect(config.defaultProviderId, symmetricAesGcmCryptoProviderId);
      expect(config.lookup(nskeyCryptoProviderId), isA<NskeyProvider>());
      expect(config.lookup(symmetricAesGcmCryptoProviderId),
          isA<SymmetricAesGcmProvider>());
    });

    test('hands every part the same cache', () async {
      // The parts are not independent: a conveyance caches a CK that the data
      // provider must then find. Separate caches would fail silently at the
      // first write, which is exactly why the SDK assembles this.
      final ring = InMemoryNskeyKeyRing()
        ..seedKeypair(owner, namespace,
            publicKey: aliceNskey.publicKeyBytes,
            privateKey: aliceNskey.privateKeyBytes);
      final c = configured(ring);
      final valueKey = selfValue('treaty');

      await CryptoRuntime(c.client)
          .prepareForPut(valueKey, symmetricAesGcmCryptoProviderId);
      // The transformer stamps the routing id before encrypting; CryptoRuntime
      // resolves the provider from it, so the test has to do the same.
      valueKey.metadata.appMetadata =
          AppMetadata(providerId: symmetricAesGcmCryptoProviderId);
      final ciphertext =
          await CryptoRuntime(c.client).encryptForPut(valueKey, 'the treaty');

      expect(c.written, hasLength(1), reason: 'one conveyance was written');
      expect(ciphertext, isNotEmpty);
      expect(valueKey.metadata.appMetadata!.providerId,
          symmetricAesGcmCryptoProviderId);
      expect(valueKey.metadata.appMetadata!.additional!['ckKid'], isNotNull);
    });

    test('gives each call its own state, so two atSigns cannot share', () {
      final ring = InMemoryNskeyKeyRing();
      final a = CryptoConfig.nskey(keyRing: ring);
      final b = CryptoConfig.nskey(keyRing: ring);
      expect(
          identical(
              a.lookup(nskeyCryptoProviderId), b.lookup(nskeyCryptoProviderId)),
          isFalse,
          reason: 'these providers hold per-atSign state; sharing one set '
              'across atSigns would cross their content keys');
    });
  });

  group('the manager and the data provider compose', () {
    test('a value encrypts straight after ensureCurrent, with no manual convey',
        () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      final data =
          SymmetricAesGcmProvider(cache: c.cache, ckManager: c.manager);

      final valueKey = selfValue('treaty');
      // Exactly what the pipeline does: prepare, then encrypt.
      await data.prepareForWrite(c.context, valueKey);
      final ciphertext =
          await data.encrypt(c.context, valueKey, 'the treaty text');

      expect(ciphertext, isNotEmpty);
      expect(valueKey.metadata.appMetadata!.additional!['ckKid'],
          c.cache.current(owner, namespace)!.ckKid);
    });

    test('without the manager the data provider still refuses, as before',
        () async {
      final c = client();
      final data = SymmetricAesGcmProvider(cache: c.cache);
      await data.prepareForWrite(c.context, selfValue('treaty'));
      await expectLater(
        data.encrypt(c.context, selfValue('treaty'), 'x'),
        throwsA(isA<AtEncryptionException>()),
      );
    });
  });
}
