import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The nskey data path over a **nested** namespace.
///
/// Two things make this its own file. First, `AtKey.fromString` splits at the
/// last dot, so `someid.d.c.b.a@alice` parses back as `key = someid.d.c.b`,
/// `namespace = a` — a multi-segment namespace cannot be recovered from the wire
/// string, and every path that re-parses a key (sync pull, both notify
/// directions) sees the wrong split. Second, `AtCollection` composes
/// sub-collection namespaces as `<subName>.<parentId>.<ns>` with a per-**item**
/// id, so an exact-match nskey rule would need a keypair per item.
///
/// Resolution therefore walks up, and the records state their namespaces. Both
/// facts are only visible with more than one segment, which is why the rest of
/// the suite — and both live suites — never showed them.
void main() {
  const alice = '@alice';
  // Multi-segment on purpose: with a single-segment app namespace the
  // last-dot split lands on it by coincidence and nothing is proven.
  const appNs = 'app_1.my_apps';
  const composedNs = '__rr.item123.app_1.my_apps';

  late XWingKeyPair appKey;

  setUpAll(() async {
    appKey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  late CryptoContext context;
  late MockAtClient atClient;
  late Map<String, ({AtKey key, String value})> store;

  /// A client holding the app-namespace keypair and nothing deeper — the
  /// ordinary state after eager minting, which mints for the preference
  /// namespace and the enrollment's `rw` namespaces, never per item.
  ({
    NskeyProvider nskey,
    SymmetricAesGcmProvider data,
    CkManager manager,
    ContentKeyCache cache,
    InMemoryNskeyKeyRing ring,
  }) client() {
    final cache = ContentKeyCache();
    final ring = InMemoryNskeyKeyRing()
      ..seedKeypair(alice, appNs,
          publicKey: appKey.publicKeyBytes, privateKey: appKey.privateKeyBytes);
    final nskey = NskeyProvider(keyRing: ring, cache: cache);
    final manager = CkManager(cache: cache, keyRing: ring);
    return (
      nskey: nskey,
      data: SymmetricAesGcmProvider(cache: cache, ckManager: manager),
      manager: manager,
      cache: cache,
      ring: ring,
    );
  }

  setUp(() {
    store = {};
    atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    context = CryptoContext(atClient: atClient);
  });

  /// Wires the mock so a conveyance `put` from `CkManager` is sealed by the
  /// `at/nskey` provider and kept, and a later `get` replays it — which is what
  /// the real pipeline does either side of storage.
  void wireConveyance(
      ({
        NskeyProvider nskey,
        SymmetricAesGcmProvider data,
        CkManager manager,
        ContentKeyCache cache,
        InMemoryNskeyKeyRing ring,
      }) c) {
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final sealed =
          await c.nskey.encrypt(context, key, inv.positionalArguments[1]);
      store[key.toString()] = (key: key, value: sealed);
      return true;
    });
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final asked = inv.positionalArguments[0] as AtKey;
      final held = store[asked.toString()];
      if (held == null) throw KeyNotFoundException(asked.toString());
      // The reader re-parses the record from its wire string, which is the
      // whole point: it is what sync and notify do, and it is where a
      // multi-segment namespace is lost.
      final reparsed = AtKey.fromString(held.key.toString())
        ..metadata.appMetadata = held.key.metadata.appMetadata;
      await c.nskey.decrypt(context, reparsed, held.value);
      return AtValue()..value = held.value;
    });
  }

  AtKey value(String name, String namespace) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = alice
    ..metadata = Metadata();

  test('a composed namespace resolves to the app namespace and round-trips',
      () async {
    final c = client();
    wireConveyance(c);
    final valueKey = value('someid', composedNs);

    await c.manager.ensureCurrent(context, valueKey);
    final ciphertext = await c.data.encrypt(context, valueKey, 'the memo');

    final meta = valueKey.metadata.appMetadata!.additional!;
    expect(meta['ns'], composedNs,
        reason: 'the value states its own namespace');
    expect(meta['ckNs'], appNs,
        reason: 'the CK lives where the nskey was found, one level up');

    // One conveyance, addressed at the resolved namespace — not one per item.
    expect(store.keys.single, contains('.__ck.$appNs$alice'));

    // The reader's view: parsed from the wire, so its own namespace field is
    // the wrong split. It must still decrypt.
    final asRead = AtKey.fromString(valueKey.toString())
      ..metadata.appMetadata = valueKey.metadata.appMetadata;
    expect(asRead.namespace, 'my_apps',
        reason: 'the last-dot split — the reader genuinely sees this, and it '
            'is neither the value\'s namespace nor the CK\'s');
    expect(asRead.key, 'someid.__rr.item123.app_1',
        reason: 'and the identifier absorbed the rest');

    expect(await c.data.decrypt(context, asRead, ciphertext), 'the memo',
        reason: 'the record carries what the split destroyed');
  });

  test('a second client opens the conveyance and reads, both from the wire',
      () async {
    // The case the writer's own cache hides: a client that has never seen the
    // content key has to open the conveyance record — and it sees that record
    // as the wire gives it, mis-split. Without the conveyance stating its own
    // namespace it would look for the private under `my_apps` and find none.
    final writer = client();
    wireConveyance(writer);
    final valueKey = value('someid', composedNs);
    await writer.manager.ensureCurrent(context, valueKey);
    final ciphertext = await writer.data.encrypt(context, valueKey, 'the memo');

    final held = store.values.single;
    final conveyanceFromWire = AtKey.fromString(held.key.toString())
      ..metadata.appMetadata = held.key.metadata.appMetadata;
    expect(conveyanceFromWire.namespace, 'my_apps',
        reason: 'the conveyance key is mis-split exactly like the value');

    final reader = client();
    expect(reader.cache.get(alice, appNs, 'anything'), isNull);
    await reader.nskey.decrypt(context, conveyanceFromWire, held.value);

    final valueFromWire = AtKey.fromString(valueKey.toString())
      ..metadata.appMetadata = valueKey.metadata.appMetadata;
    expect(await reader.data.decrypt(context, valueFromWire, ciphertext),
        'the memo');
  });

  test('two items under one app namespace share a content key', () async {
    final c = client();
    wireConveyance(c);

    final first = value('a', '__rr.item123.app_1.my_apps');
    await c.manager.ensureCurrent(context, first);
    await c.data.encrypt(context, first, 'one');

    final second = value('b', '__rr.item124.app_1.my_apps');
    await c.manager.ensureCurrent(context, second);
    await c.data.encrypt(context, second, 'two');

    expect(first.metadata.appMetadata!.additional!['ckKid'],
        second.metadata.appMetadata!.additional!['ckKid'],
        reason: 'a CK per item would mean a conveyance record per item, which '
            'is what walking up exists to avoid');
    expect(store, hasLength(1), reason: 'and one conveyance record, not two');
  });

  test('a value cannot be relocated to another item under the same key',
      () async {
    // The AAD binds the record's full address, so the shared CK does not make
    // two sub-collection items interchangeable.
    final c = client();
    wireConveyance(c);

    final first = value('a', '__rr.item123.app_1.my_apps');
    await c.manager.ensureCurrent(context, first);
    final ciphertext = await c.data.encrypt(context, first, 'one');

    final elsewhere = value('a', '__rr.item124.app_1.my_apps')
      ..metadata.appMetadata = first.metadata.appMetadata;

    await expectLater(c.data.decrypt(context, elsewhere, ciphertext),
        throwsA(isA<AtException>()),
        reason: 'sharing a content key must not make records swappable');
  });

  test('a deeper key wins once it exists', () async {
    final c = client();
    wireConveyance(c);
    final deep = await XWingKeyPair.generate();
    c.ring.seedKeypair(alice, 'item123.app_1.my_apps',
        publicKey: deep.publicKeyBytes, privateKey: deep.privateKeyBytes);

    final valueKey = value('someid', composedNs);
    await c.manager.ensureCurrent(context, valueKey);
    await c.data.encrypt(context, valueKey, 'the memo');

    expect(valueKey.metadata.appMetadata!.additional!['ckNs'],
        'item123.app_1.my_apps',
        reason: 'most specific first');
  });

  test('a namespace with no key at any level is cold start', () async {
    final c = client();

    await expectLater(
      c.manager.ensureCurrent(context, value('x', 'a.b.never_used')),
      throwsA(isA<NamespaceKeyUnavailableException>()
          .having((e) => e.namespace, 'namespace', 'a.b.never_used')),
      reason: 'the whole walk is exhausted, not just the first level',
    );
  });
}
