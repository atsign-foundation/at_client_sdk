import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
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
/// A [CurrentCkPointer] backed by a plain map, standing in for the self key
/// the real one writes. Survives a simulated restart, which is the whole
/// point of the thing under test.
class InMemoryCkPointer extends CurrentCkPointer {
  final Map<String, CurrentCk> _remembered = {};

  InMemoryCkPointer() : super();

  @override
  Future<CurrentCk?> read(AtClient atClient, String owner, String ckNs) async =>
      _remembered['$owner|$ckNs'];

  @override
  Future<void> write(AtClient atClient, String owner, String ckNs, String ckKid,
          String nskeyKid) async =>
      _remembered['$owner|$ckNs'] = (ckKid: ckKid, nskeyKid: nskeyKid);
}

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
  ///
  /// [failWrites] makes the first N conveyance writes fail *after* the record
  /// has been encrypted — the real shape of the hazard, since encryption
  /// happens in the put transformer and the write is issued after it.
  ({
    CkManager manager,
    CryptoContext context,
    InMemoryNskeyKeyRing ring,
    ContentKeyCache cache,
    List<AtKey> written,
    List<AtKey> deleted,
    List<String?> providerIds,
    List<bool?> routings,
    InMemoryCkPointer pointer,
    CkManager Function(ContentKeyCache) coldManager,
    void Function() failNextWrite,
  }) client({int failWrites = 0, bool failDeletes = false}) {
    var writesLeftToFail = failWrites;
    final cache = ContentKeyCache();
    final ring = InMemoryNskeyKeyRing();
    final nskey = NskeyProvider(keyRing: ring, cache: cache);
    final pointer = InMemoryCkPointer();
    final manager = CkManager(cache: cache, keyRing: ring, pointer: pointer);
    // A restart replaces the whole config — provider and manager share one
    // cache in production, so a cold manager needs a cold provider with it.
    // Reads must decrypt through whichever is live, or the recovered CK lands
    // in a cache nobody is looking at.
    var activeNskey = nskey;
    // Conveyance ciphertexts, so a read can be served the way sync would.
    final conveyed = <String, String>{};
    // The KEY as well as the value: encrypt stamps appMetadata onto it
    // (the nskey generation the CK was sealed to), and a real get returns
    // that stored metadata with the record. Handing decrypt a freshly built
    // key instead would leave it unable to tell which generation to open.
    final conveyedKeys = <String, AtKey>{};
    final written = <AtKey>[];
    final deleted = <AtKey>[];
    final providerIds = <String?>[];
    final routings = <bool?>[];

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
      // The current-CK pointer writes an ordinary self key through the same
      // client. It is not a conveyance and does not go through the nskey
      // provider, so it is ignored here entirely — these assertions are about
      // how many CKs were cut, and counting unrelated puts would make every
      // one of them a coincidence.
      if (key.key?.startsWith('__ckcur') == true) {
        return true;
      }
      written.add(key);
      providerIds.add(options?.cryptoProviderId);
      routings.add(options?.useRemoteAtServer);
      conveyed[key.toString()] = await nskey.encrypt(context, key, value);
      conveyedKeys[key.toString()] = key;
      if (writesLeftToFail > 0) {
        writesLeftToFail--;
        throw SecondaryConnectException('conveyance write failed');
      }
      return true;
    });

    when(() => mockAtClient.delete(any(),
            isDedicated: any(named: 'isDedicated'),
            deleteRequestOptions: any(named: 'deleteRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      if (failDeletes) {
        throw SecondaryConnectException('conveyance delete failed');
      }
      deleted.add(key);
      // The record is gone from the store too, so a reader can no longer
      // recover the CK it carried — which is the whole point of deleting it.
      conveyed.remove(key.toString());
      conveyedKeys.remove(key.toString());
      return true;
    });

    when(() => mockAtClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((inv) {
      final key = inv.positionalArguments[0] as AtKey;
      final ciphertext = conveyed[key.toString()];
      if (ciphertext == null) throw AtKeyNotFoundException('$key not found');
      // Routes back through at/nskey, which decapsulates and caches the CK as
      // a side effect — exactly what the production read path relies on.
      return activeNskey
          .decrypt(CryptoContext(atClient: mockAtClient),
              conveyedKeys[key.toString()]!, ciphertext)
          .then((plain) => AtValue()..value = plain);
    });
    when(() => mockAtClient.get(any())).thenAnswer((inv) {
      final key = inv.positionalArguments[0] as AtKey;
      final ciphertext = conveyed[key.toString()];
      if (ciphertext == null) throw AtKeyNotFoundException('$key not found');
      return activeNskey
          .decrypt(CryptoContext(atClient: mockAtClient),
              conveyedKeys[key.toString()]!, ciphertext)
          .then((plain) => AtValue()..value = plain);
    });

    return (
      manager: manager,
      context: context,
      ring: ring,
      cache: cache,
      pointer: pointer,
      coldManager: (ContentKeyCache c) {
        activeNskey = NskeyProvider(keyRing: ring, cache: c);
        return CkManager(cache: c, keyRing: ring, pointer: pointer);
      },
      written: written,
      deleted: deleted,
      providerIds: providerIds,
      routings: routings,
      failNextWrite: () => writesLeftToFail = 1,
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

    /// A CK is only usable if the record conveying it exists. Marking one
    /// current before that write lands means a failure leaves the cache
    /// claiming a key nobody was ever sent — and `ensureCurrent`'s
    /// already-current guard then short-circuits forever, so every later value
    /// encrypts under it and is silently undecryptable.
    test('a failed conveyance write leaves no current CK', () async {
      final c = client(failWrites: 1);
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await expectLater(c.manager.ensureCurrent(c.context, selfValue('treaty')),
          throwsA(isA<SecondaryConnectException>()));

      expect(c.cache.current(owner, namespace), isNull,
          reason: 'the conveyance record does not exist, so nothing may claim '
              'to be the key new writes encrypt under');
    });

    test('a retry after a failed conveyance write conveys a fresh CK',
        () async {
      final c = client(failWrites: 1);
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await expectLater(c.manager.ensureCurrent(c.context, selfValue('treaty')),
          throwsA(isA<SecondaryConnectException>()));
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));

      expect(c.written, hasLength(2),
          reason: 'the first conveyance never landed, so the retry must cut '
              'and convey another rather than reuse the orphan');
      expect(c.cache.current(owner, namespace), isNotNull);
      expect(c.cache.current(owner, namespace)!.ckKid,
          c.written.last.key.replaceAll('.__ck', ''),
          reason: 'the current CK must be the one whose conveyance landed');
    });

    /// The conveyance carries the key the value cites, so it must not be
    /// slower than the value. A per-call `useRemoteAtServer: true` sends the
    /// value straight to the atServer; leaving the conveyance on the default
    /// local-first route means the recipient can see a value whose key is
    /// still sitting on the sender's device — until the next sync, or forever
    /// if the process exits first.
    test(
        'a restart resumes the CK it was writing under rather than cutting '
        'another', () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      final valueKey = selfValue('treaty');

      await c.manager.ensureCurrent(c.context, valueKey);
      expect(c.written, hasLength(1), reason: 'the first write cuts a CK');
      final firstKid = c.cache.current(owner, namespace)!.ckKid;

      // Same durable state, empty cache — a restart. Without the pointer this
      // finds nothing and mints, leaving a second conveyance record that can
      // never be cleaned up, because data written under the first still needs
      // it.
      final cold = c.coldManager(ContentKeyCache());
      final resumed =
          await c.pointer.read(c.context.atClient, owner, namespace);
      await cold.ensureCurrent(c.context, valueKey);

      expect(c.written, hasLength(1),
          reason: 'the CK it was already writing under is recovered from its '
              'own conveyance record, so no second record is written');
      expect(cold.cache.current(owner, namespace)!.ckKid, firstKid,
          reason: 'and it is the same key, so readers of data written before '
              'the restart and after it need only the one');
    });

    test('the conveyance follows the outer write to the remote atServer',
        () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await c.manager.ensureCurrent(c.context, selfValue('treaty'),
          useRemoteAtServer: true);

      expect(c.routings.single, isTrue,
          reason: 'a value written remote-only must not cite a conveyance that '
              'only exists locally');
    });

    test('the conveyance follows a local-first outer write too', () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));

      expect(c.routings.single, isFalse,
          reason: 'with no override the conveyance takes the same default '
              'route the value takes');
    });

    test('refuses, by name, when the destination has no nskey at all',
        () async {
      final c = client();
      // No seeding: @bob has never used this namespace. Raising it here rather
      // than mid-pipeline is what leaves the caller free to route the write to
      // legacy instead — nothing has been committed to yet.
      await expectLater(
        c.manager.ensureCurrent(c.context, sharedValue('treaty')),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.atSign, 'atSign', bob)
            .having((e) => e.namespace, 'namespace', namespace)),
        reason: 'an app has to be able to say "@bob has not enabled this" '
            'rather than surface an encryption error',
      );
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
        // The current-CK pointer writes an ordinary self key through this
        // same client; it is not a conveyance, so it is not counted here.
        if (key.key?.startsWith('__ckcur') == true) return true;
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

  group('rotateContentKey', () {
    test('cuts a successor and leaves the superseded conveyance in place',
        () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      final superseded = c.cache.current(owner, namespace)!;

      final rotated =
          await c.manager.rotateContentKey(c.context, selfValue('treaty'));

      expect(rotated.ckKid, isNot(superseded.ckKid));
      expect(c.cache.current(owner, namespace)!.ckKid, rotated.ckKid,
          reason: 'new writes encrypt under the successor');
      expect(c.deleted, isEmpty,
          reason: 'retaining the old conveyance is the DEFAULT: it is what '
              'lets a late-joining enrollment read history, which is the '
              'legacy-like behaviour most apps expect');
      expect(c.cache.get(owner, namespace, superseded.ckKid), isNotNull,
          reason: 'and data written under it still decrypts');
    });

    test('deleteSuperseded removes the old conveyance and evicts the key',
        () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      final superseded = c.cache.current(owner, namespace)!;

      await c.manager.rotateContentKey(c.context, selfValue('treaty'),
          deleteSuperseded: true);

      expect(c.deleted.map((k) => k.key), ['${superseded.ckKid}.__ck'],
          reason: 'the record carrying the old CK is what makes it '
              'unwrappable — the nskey private cannot help once no sealed '
              'copy survives');
      expect(c.cache.get(owner, namespace, superseded.ckKid), isNull,
          reason: 'and this client must stop using the copy it already '
              'unwrapped, or the deletion closes off nobody');
    });

    test('deletes only after the successor is durable', () async {
      // A conveyance write that fails must leave the old CK alone. Deleting
      // first would strand the destination with no readable past AND no key
      // to write the next value under.
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      final superseded = c.cache.current(owner, namespace)!;
      c.failNextWrite();

      await expectLater(
          c.manager.rotateContentKey(c.context, selfValue('treaty'),
              deleteSuperseded: true),
          throwsA(isA<SecondaryConnectException>()));

      expect(c.deleted, isEmpty);
      expect(c.cache.current(owner, namespace)!.ckKid, superseded.ckKid,
          reason: 'the destination keeps a working key');
    });

    test('a delete that fails is loud, and the successor still stands',
        () async {
      final c = client(failDeletes: true);
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      final superseded = c.cache.current(owner, namespace)!;

      final rotated = await c.manager.rotateContentKey(
          c.context, selfValue('treaty'),
          deleteSuperseded: true);

      expect(rotated.ckKid, isNot(superseded.ckKid),
          reason: 'writes are correct from here on; what was not achieved is '
              'the forward secrecy, and that is a log, not an exception that '
              'would roll back a good rotation');
      expect(c.cache.current(owner, namespace)!.ckKid, rotated.ckKid);
    });

    test('supersedes the CK a previous process cut, read off the pointer',
        () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      final superseded = c.cache.current(owner, namespace)!;

      // A restart: a fresh cache and manager, with only the pointer surviving.
      final coldCache = ContentKeyCache();
      final cold = c.coldManager(coldCache);

      await cold.rotateContentKey(c.context, selfValue('treaty'),
          deleteSuperseded: true);

      expect(c.deleted.map((k) => k.key), ['${superseded.ckKid}.__ck'],
          reason: 'without the pointer a rotation from a freshly started '
              'client supersedes nothing and leaves the old conveyance live — '
              'the FS it was asked for silently not done');
    });

    test('a destination with no published nskey cannot be rotated', () async {
      final c = client();

      await expectLater(
          c.manager.rotateContentKey(c.context, sharedValue('treaty')),
          throwsA(isA<NamespaceKeyUnavailableException>()),
          reason: 'there is nothing to seal the successor to, and unlike a '
              'write there is no legacy path to reroute a rotation onto');
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
