import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// A [CurrentCkPointer] backed by a plain map, standing in for the self key the
/// real one writes, and surviving a simulated restart.
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

/// An [InMemoryNskeyKeyRing] whose advertisement for a namespace can gain a
/// second algorithm's entry after the fact.
///
/// Widening retains the entry already published and the generation's own mint
/// time: replacing either would be a rotation, and every record sealed to the
/// old entry would need conveying again.
class _WidenableRing extends InMemoryNskeyKeyRing {
  final Map<String, NskeyAdvertisement> _widened = {};

  /// Republish `(owner, namespace)` carrying [added] beside what it already
  /// advertises, listed **first** — where a reader walking the record's own
  /// order rather than its own preference would find it.
  Future<void> widen(String owner, String namespace, PackageKey added) async {
    final published = (await super.currentPublic(owner, namespace))!;
    _widened['$owner|$namespace'] = NskeyAdvertisement(
        v: published.v,
        createdAt: published.createdAt,
        keys: [added, ...published.keys]);
  }

  @override
  Future<NskeyAdvertisement?> currentPublic(
          String owner, String namespace) async =>
      _widened['$owner|$namespace'] ??
      await super.currentPublic(owner, namespace);
}

/// The CK manager — the step that makes `put` work at all on the nskey path.
///
/// Content keys are scoped per recipient, so "no current CK" fires on the first
/// write to every new destination and again whenever that destination rotates;
/// minting one writes a conveyance record, which is why this runs before the
/// write pipeline rather than inside `encrypt`.
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
  /// [failWrites] fails the first N conveyance writes *after* the record has
  /// been encrypted, and [keyRing] replaces the ring the fixture would build.
  /// [sealsToKeyAlgorithms] and [nskeyKeyAlgo] move together: the manager
  /// stamps a provider id chosen from the destination's advertisement, and the
  /// runtime dispatches the conveyance write to it.
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
    DateTime conveyanceCreatedAt,
    CkManager Function(ContentKeyCache,
        {CkRotationPolicy ckRotationPolicy}) coldManager,
    void Function() failNextWrite,
  }) client(
      {int failWrites = 0,
      bool failDeletes = false,
      InMemoryNskeyKeyRing? keyRing,
      List<String> sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos,
      String nskeyKeyAlgo = SecretSharingAlgos.xWing,
      CkRotationPolicy ckRotationPolicy = rotateCkAfterOneWeek}) {
    var writesLeftToFail = failWrites;
    // NOTE: a fixed date — an assertion that matched `now` would pass whether
    // the age came from the record or from this device's clock.
    final conveyanceCreatedAt = DateTime.utc(2026, 3, 4, 5, 6, 7);
    final cache = ContentKeyCache();
    final ring = keyRing ?? InMemoryNskeyKeyRing();
    final nskey =
        NskeyProvider(keyRing: ring, cache: cache, keyAlgo: nskeyKeyAlgo);
    final pointer = InMemoryCkPointer();
    final manager = CkManager(
        cache: cache,
        keyRing: ring,
        pointer: pointer,
        sealsToKeyAlgorithms: sealsToKeyAlgorithms,
        ckRotationPolicy: ckRotationPolicy);
    // NOTE: provider and manager share one cache in production, so a cold
    // manager needs a cold provider with it, and reads must decrypt through
    // whichever is live.
    var activeNskey = nskey;
    // Conveyance ciphertexts, so a read can be served the way sync would.
    final conveyed = <String, String>{};
    // NOTE: the key as well as the value — encrypt stamps the sealed-to nskey
    // generation onto its appMetadata, and decrypt needs that same key back to
    // tell which generation to open.
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
      // The current-CK pointer writes an ordinary self key through this same
      // client; it is not a conveyance, so it is not counted here.
      if (key.key.startsWith('__ckcur') == true) {
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
      conveyed.remove(key.toString());
      conveyedKeys.remove(key.toString());
      return true;
    });

    when(() => mockAtClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((inv) {
      final key = inv.positionalArguments[0] as AtKey;
      final ciphertext = conveyed[key.toString()];
      if (ciphertext == null) throw AtKeyNotFoundException('$key not found');
      // at/nskey decapsulates and caches the CK as a side effect, which is what
      // the production read path relies on.
      return activeNskey
          .decrypt(CryptoContext(atClient: mockAtClient),
              conveyedKeys[key.toString()]!, ciphertext)
          // The record's own createdAt: a resumed CK takes its cut-time from
          // the atServer's date, the only one two devices can agree on.
          .then((plain) => AtValue()
            ..value = plain
            ..metadata = (Metadata()..createdAt = conveyanceCreatedAt));
    });
    when(() => mockAtClient.get(any())).thenAnswer((inv) {
      final key = inv.positionalArguments[0] as AtKey;
      final ciphertext = conveyed[key.toString()];
      if (ciphertext == null) throw AtKeyNotFoundException('$key not found');
      return activeNskey
          .decrypt(CryptoContext(atClient: mockAtClient),
              conveyedKeys[key.toString()]!, ciphertext)
          // NOTE: the resume path takes this one-argument overload, so the
          // record's date has to be stamped here as well as on the other stub.
          .then((plain) => AtValue()
            ..value = plain
            ..metadata = (Metadata()..createdAt = conveyanceCreatedAt));
    });

    return (
      manager: manager,
      context: context,
      ring: ring,
      cache: cache,
      pointer: pointer,
      conveyanceCreatedAt: conveyanceCreatedAt,
      coldManager: (ContentKeyCache c,
          {CkRotationPolicy ckRotationPolicy = rotateCkAfterOneWeek}) {
        activeNskey =
            NskeyProvider(keyRing: ring, cache: c, keyAlgo: nskeyKeyAlgo);
        return CkManager(
            cache: c,
            keyRing: ring,
            pointer: pointer,
            sealsToKeyAlgorithms: sealsToKeyAlgorithms,
            ckRotationPolicy: ckRotationPolicy);
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

    test('an algorithm added to the advertisement is nothing to re-seal',
        () async {
      // NOTE: counted over THIS client alone. A sibling enrollment that missed
      // the push does pull the added private at its next start, by design, and
      // counting that would read correct behaviour as a violation.
      final ring = _WidenableRing();
      final c = client(keyRing: ring);
      ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      final published = (await ring.currentPublic(owner, namespace))!;

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      final ckKid = c.cache.current(owner, namespace)!.ckKid;
      final sealedTo = c.cache.currentNskeyKid(owner, namespace);

      final mlKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
      final second = await mlKem.keyPairFromSeed(mlKem.newSeed());
      final added = PackageKey.fromBytes(
          use: SecretSharingAlgos.useEnc,
          alg: SecretSharingAlgos.mlKem1024,
          pub: second.publicKey);
      await ring.widen(owner, namespace, added);

      // The control: these three checks say the widening actually landed, so
      // the absences below are read against a changed advertisement.
      final republished = (await ring.currentPublic(owner, namespace))!;
      expect(republished.keys.map((k) => k.alg),
          [SecretSharingAlgos.mlKem1024, SecretSharingAlgos.xWing]);
      expect(republished.keys.last.kid, sealedTo);
      expect(republished.createdAt, published.createdAt,
          reason: 'an ADD rather than a re-mint: the entry already published '
              'and the generation\'s own mint time both survive it, which is '
              'what separates widening from rotating');

      await c.manager.ensureCurrent(c.context, selfValue('other'));

      expect(c.written, hasLength(1),
          reason: 'the conveyance from before the widening is still the only '
              'one — an added algorithm gives the publisher nothing to '
              're-seal and nobody to re-convey to');
      expect(c.cache.current(owner, namespace)!.ckKid, ckKid,
          reason: 'and values written after it encrypt under the content key '
              'that was already current');
      expect(c.cache.currentNskeyKid(owner, namespace), sealedTo,
          reason: 'sealed to the entry it was sealed to before, so nothing in '
              'this client\'s own state records that its advertisement grew');
    });

    test('a restart after the widening resumes rather than cutting another',
        () async {
      // The durable half of the same absence: what a client remembers about a
      // destination is a generation kid, and the widened advertisement must
      // still resolve to it.
      final ring = _WidenableRing();
      final c = client(keyRing: ring);
      ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      final valueKey = selfValue('treaty');

      await c.manager.ensureCurrent(c.context, valueKey);
      final ckKid = c.cache.current(owner, namespace)!.ckKid;

      final mlKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
      final second = await mlKem.keyPairFromSeed(mlKem.newSeed());
      await ring.widen(
          owner,
          namespace,
          PackageKey.fromBytes(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.mlKem1024,
              pub: second.publicKey));
      expect((await ring.currentPublic(owner, namespace))!.keys, hasLength(2),
          reason: 'the control: the record really did gain an entry, so the '
              'absence below is measured against a widening rather than '
              'against a ring that ignored the call');

      // Same durable state, empty cache — a restart, with the wider
      // advertisement now the one it reads.
      final cold = c.coldManager(ContentKeyCache());
      await cold.ensureCurrent(c.context, valueKey);

      expect(c.written, hasLength(1),
          reason: 'the pointer still names a generation the advertisement '
              'offers, so the CK it was already writing under is recovered '
              'from its own conveyance record rather than replaced');
      expect(cold.cache.current(owner, namespace)!.ckKid, ckKid,
          reason: 'and it is the same key, so nothing written before the '
              'widening needs a second conveyance to stay readable');
    });

    test(
        'a narrowed writer seals to the algorithm it added to its own '
        'advertisement', () async {
      // The destination is @alice herself, so the advertisement the write
      // consults is the one this atSign widened: the resolver finds an entry on
      // the narrowed list and the refusal under that lookup is never reached.
      final ring = _WidenableRing();
      final c = client(
          keyRing: ring,
          sealsToKeyAlgorithms: const [SecretSharingAlgos.mlKem1024],
          nskeyKeyAlgo: SecretSharingAlgos.mlKem1024);
      ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      final mlKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
      final second = await mlKem.keyPairFromSeed(mlKem.newSeed());
      final added = PackageKey.fromBytes(
          use: SecretSharingAlgos.useEnc,
          alg: SecretSharingAlgos.mlKem1024,
          pub: second.publicKey);
      await ring.widen(owner, namespace, added);
      expect(
          (await ring.currentPublic(owner, namespace))!.keys.map((k) => k.alg),
          [SecretSharingAlgos.mlKem1024, SecretSharingAlgos.xWing],
          reason: 'the fixture control: everything below is measured against '
              'an advertisement that really did gain the entry, not against '
              'one that stayed as seeding left it');

      await expectLater(
          c.manager.ensureCurrent(c.context, selfValue('treaty')), completes,
          reason: 'the sender and the advertisement belong to the same '
              'atSign, so there is no skew between them for a refusal to '
              'catch');

      expect(c.written, hasLength(1));
      expect(c.providerIds.single, mlKemNskeyCryptoProviderId,
          reason: 'and the conveyance went to the algorithm the narrowing '
              'names — completing while sealing under x-wing would be this '
              'same absence of a refusal with none of the behaviour');
      expect(c.cache.currentNskeyKid(owner, namespace), added.kid,
          reason: 'sealed to the added entry by kid, so what the write '
              'followed is the published advertisement rather than the '
              'client\'s own configuration');
    });

    test('the same narrowing refuses where nothing added the algorithm',
        () async {
      // The control for the arm above: the same narrowing over an
      // advertisement that was never widened, so the refusal fires.
      final c =
          client(sealsToKeyAlgorithms: const [SecretSharingAlgos.mlKem1024]);
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await expectLater(
        c.manager.ensureCurrent(c.context, selfValue('treaty')),
        throwsA(allOf(
          isA<AtEncryptionException>().having(
              (e) => e.message,
              'message',
              allOf(contains('advertises x-wing'),
                  contains('will seal to ml-kem-1024'))),
          isNot(isA<NamespaceKeyUnavailableException>()),
        )),
        reason: 'both sides of the mismatch are named, and it is NOT the '
            'cold-start exception: a client that narrowed itself must not '
            'read its own configuration as the owner having published '
            'nothing',
      );
      expect(c.written, isEmpty,
          reason: 'refused before a content key is cut, so there is no '
              'orphan conveyance to reconcile afterwards');
    });

    test('the default policy leaves a fresh content key alone', () async {
      // The control for the arm below: a key cut a moment ago is not a week
      // old, so the default policy re-cuts nothing.
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      await c.manager.ensureCurrent(c.context, selfValue('other'));

      expect(c.written, hasLength(1));
    });

    test('a policy that says yes cuts a fresh content key', () async {
      final asked = <CkRotationContext>[];
      final c = client(ckRotationPolicy: (ck) {
        asked.add(ck);
        return true;
      });
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      final first = c.cache.current(owner, namespace)!.ckKid;
      expect(asked, isEmpty,
          reason: 'there was no content key to have an opinion about — the '
              'first call cuts one, and asking would be asking about nothing');

      await c.manager.ensureCurrent(c.context, selfValue('other'));

      expect(c.written, hasLength(2),
          reason: 'the second write found a current CK against an unchanged '
              'generation, which is exactly the case the policy decides');
      expect(c.cache.current(owner, namespace)!.ckKid, isNot(first));

      expect(asked, hasLength(1));
      expect(asked.single.destination, owner);
      expect(asked.single.namespace, namespace);
      expect(asked.single.ckKid, first,
          reason: 'the policy is told which key it is deciding about, or an '
              'application cannot answer differently for different ones');
      expect(asked.single.age.isNegative, isFalse,
          reason: 'and how old it is, measured against a now the caller passes '
              'so a policy needs no clock of its own');
    });

    test('the namespace-key hook is asked only where this atSign owns the key',
        () async {
      // A content key is sealed to the DESTINATION's namespace key, so a
      // sender cannot replace a peer's.
      final asked = <String>[];
      final c = client();
      c.manager.rotateOwnNamespaceKeyIfAsked = (ns) async {
        asked.add(ns);
        return false;
      };
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      c.ring.seedPublicOnly(bob, namespace, publicKey: bobNskey.publicKeyBytes);

      await c.manager.ensureCurrent(c.context, sharedValue('pact'));
      expect(asked, isEmpty,
          reason: 'the destination is @bob, whose namespace key is his');

      await c.manager.ensureCurrent(c.context, selfValue('treaty'));
      expect(asked, [namespace],
          reason: 'and asked once for this atSign\'s own, which it can act on');
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

      final toBob = c.written.last;
      expect(toBob.sharedWith, bob);
      expect(toBob.sharedBy, owner);
    });

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

      // Same durable state, empty cache — a restart.
      final cold = c.coldManager(ContentKeyCache());
      final resumed =
          await c.pointer.read(c.context.atClient, owner, namespace);
      expect(resumed, isNotNull,
          reason: 'the control arm: the pointer is what survives the restart, '
              'so if it held nothing the recovery below would be measuring a '
              'cache that was never cold');
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
      // No seeding: @bob has never used this namespace.
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
        if (key.key.startsWith('__ckcur') == true) return true;
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
      // A conveyance caches a CK the data provider must then find; separate
      // caches would fail silently at the first write.
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
      // Deleting first would strand the destination with no readable past and
      // no key to write the next value under.
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

    test('a resumed content key takes its age from the record, not this clock',
        () async {
      final c = client();
      c.ring.seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
      await c.manager.ensureCurrent(c.context, selfValue('treaty'));

      // A restart: a fresh cache and manager, with only the pointer surviving.
      final asked = <CkRotationContext>[];
      final cold = c.coldManager(ContentKeyCache(), ckRotationPolicy: (ck) {
        asked.add(ck);
        return false;
      });

      await cold.ensureCurrent(c.context, selfValue('treaty'));
      expect(asked, isEmpty, reason: 'the resume itself decides nothing');

      await cold.ensureCurrent(c.context, selfValue('other'));

      expect(asked.single.cutAt, c.conveyanceCreatedAt,
          reason: 'the atServer\'s date for the record that carries the key. '
              'Taking this process\'s clock instead would report a key cut '
              'weeks ago as brand new, and a policy measured in days would '
              'never fire on any client that restarts');
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
