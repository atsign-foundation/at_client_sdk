import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/secret_sharing/key_package_minting.dart'
    show KeyPackageMinting;
import 'package:at_client/src/secret_sharing/key_package_persistence.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';
import 'test_utils/unreadable_keys_io.dart';

import 'fake_enrollment_directory.dart';

/// A bare host for the registration mixins, so a test can call `register()`
/// without a full client.
class TestRegistrant
    with ApkamSigning, EnvelopeSigning, KeyPackageRegistration {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestRegistrant');

  @override
  final ({Duration cacheExpiry})? publicKeyCacheSettings = null;

  TestRegistrant(this.atClient);
}

/// Backing the registration mixin's encapsulation keypair with the keyfile.
///
/// A sender addresses an envelope to the `kpid` it read from the enrollment
/// record, so a client whose kpid moves between processes scans for an address
/// nobody writes to and can be sent nothing at all.
void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;

  setUpAll(() => registerFallbackValue(AtKey()));

  setUp(() => remoteData = {});

  MockAtClient buildMockClient() => buildRemoteBackedMockClient(
      atSign: atSign, enrollmentId: 'enroll-1', remoteData: remoteData);

  Future<TestRegistrant> boundRegistrant(AtKeysIo io) async {
    final registrant = TestRegistrant(buildMockClient())
      ..directory = FakeEnrollmentDirectory();
    bindKeyPackageToAtKeys(registrant, keysIo: io, atSign: atSign);
    await registrant.register();
    return registrant;
  }

  /// A keyfile holding both halves of one X-Wing keypair, filed under the kpid
  /// they address and without an enrollment id, as an older keyfile carries
  /// it.
  Future<(InMemoryAtKeysIo, String)> keyfileWithPackage() async {
    final pair = await XWingPureDartAlgo.instance.generateKeyPair();
    final kpid = PackageKey.computeKid(base64Encode(pair.publicKey));
    final keys = AtKeys();
    final now = DateTime.now().toUtc();
    keys.addKey(CryptographicMaterial(
      keyId: kpid,
      role: CryptographicMaterialRole.publicEncapsulation,
      algorithm: CryptographicMaterialAlgorithm.xWing,
      bytes: AtBytes(pair.publicKey),
      createdAt: now,
    ));
    keys.addKey(CryptographicMaterial(
      keyId: kpid,
      role: CryptographicMaterialRole.privateDecapsulation,
      algorithm: CryptographicMaterialAlgorithm.xWing,
      bytes: AtBytes(pair.secretKey),
      createdAt: now,
    ));
    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    return (io, kpid);
  }

  test('a client adopts the key package its enrollment advertised', () async {
    final (io, advertised) = await keyfileWithPackage();

    final registrant = await boundRegistrant(io);

    expect(registrant.kpid, advertised,
        reason: 'the private half of the advertised package has been in this '
            'keyfile since enrollment; a client that generates its own instead '
            'publishes one address and listens on another');
  });

  test('the kpid is the same across two clients built from one keyfile',
      () async {
    final (io, _) = await keyfileWithPackage();

    final first = await boundRegistrant(io);
    final second = await boundRegistrant(io);

    expect(second.kpid, first.kpid);
  });

  test('a keyfile with no package is left alone', () async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());

    await boundRegistrant(io);

    expect((await io.read(atSign)).keys, isEmpty,
        reason: 'a package is discovered from the enrollment record, which is '
            'reached afterwards only by a deliberate enroll:update, so one '
            'generated here would be an address nobody can learn — not worth '
            'mutating the keyfile at startup to produce');
  });

  test('a keyfile that cannot be read stops registration', () async {
    await expectLater(
        boundRegistrant(UnreadableKeysIo()), throwsA(isA<KeyfileUnreadable>()),
        reason: 'the package this enrollment advertised may be in that '
            'keyfile, and one generated instead answers at another address');
  });

  test('a filed nskey private is never adopted as the key package', () async {
    final (io, advertised) = await keyfileWithPackage();
    // NOTE: filed last so it sorts newest — the trap a createdAt-only rule
    // would fall into.
    await NskeyPrivateFiling(keysIo: io, atSign: atSign).file(Secret(
      namespace: 'app_1.my_apps',
      name: '${NskeyPrivateFiling.secretNamePrefix}kid-one',
      // NOTE: an X-Wing seed's length, the KEM a key package also uses.
      value: base64Encode(Uint8List.fromList(List<int>.generate(32, (i) => i))),
    ));

    final registrant = await boundRegistrant(io);

    expect(registrant.kpid, advertised,
        reason: 'an nskey private is also an X-Wing privateDecapsulation; '
            'adopting one as this client\'s recipient identity would lose it '
            'the ability to open anything addressed to it');
  });

  test('an nskey private alone does not make a key package', () async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    await NskeyPrivateFiling(keysIo: io, atSign: atSign).file(Secret(
      namespace: 'app_1.my_apps',
      name: '${NskeyPrivateFiling.secretNamePrefix}kid-one',
      // NOTE: an X-Wing seed's length, the KEM a key package also uses.
      value: base64Encode(Uint8List.fromList(List<int>.generate(32, (i) => i))),
    ));

    expect(keyPackageMaterial(await io.read(atSign)), isNull,
        reason: 'an nskey private arrives alone — its public half is published '
            'on the atServer, not kept here, and that is what tells the two '
            'apart');
  });

  test(
      'a retrofitted keyfile: each principal adopts its OWN package, never '
      'its co-tenant\'s', () async {
    // NOTE: the tagged package is the newer one, so a newest-wins rule would
    // hand it to the untagged principal too.
    final keys = AtKeys();
    final legacyPair = await XWingPureDartAlgo.instance.generateKeyPair();
    final legacyKpid =
        PackageKey.computeKid(base64Encode(legacyPair.publicKey));
    final pqPair = await XWingPureDartAlgo.instance.generateKeyPair();
    final pqKpid = PackageKey.computeKid(base64Encode(pqPair.publicKey));
    final older = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final newer = DateTime.now().toUtc();
    for (final (kpid, pair, id, at) in [
      (legacyKpid, legacyPair, null, older),
      (pqKpid, pqPair, 'pq-enrollment-1', newer),
    ]) {
      keys.addKey(CryptographicMaterial(
          keyId: kpid,
          enrollmentId: id,
          role: CryptographicMaterialRole.publicEncapsulation,
          algorithm: CryptographicMaterialAlgorithm.xWing,
          bytes: AtBytes(pair.publicKey),
          createdAt: at));
      keys.addKey(CryptographicMaterial(
          keyId: kpid,
          enrollmentId: id,
          role: CryptographicMaterialRole.privateDecapsulation,
          algorithm: CryptographicMaterialAlgorithm.xWing,
          bytes: AtBytes(pair.secretKey),
          createdAt: at));
    }

    expect(keyPackageMaterial(keys, enrollmentId: 'pq-enrollment-1')!.keyId,
        pqKpid);
    expect(keyPackageMaterial(keys)!.keyId, legacyKpid,
        reason: 'newest-wins across the whole file would hand a legacy '
            'client restarting on the shared keyfile the PQ enrollment\'s '
            'kpid — an address its own enrollment record never advertised');
    expect(keyPackageMaterial(keys, enrollmentId: 'some-other-id')!.keyId,
        legacyKpid,
        reason: 'a package tagged for a different enrollment is never '
            'adopted; the untagged pre-id-era package is the fallback');

    expect(
        keyPackageMaterials(keys, enrollmentId: 'pq-enrollment-1')
            .map((m) => m.keyId),
        [pqKpid],
        reason: 'the tagged and untagged sets do not merge — taking both '
            'would let a co-tenant\'s package into this principal\'s '
            'holding, which is the whole thing the scoping exists to stop');
    expect(keyPackageMaterials(keys).map((m) => m.keyId), [legacyKpid]);
  });

  /// Files both halves of [pair] under its kpid, for `enroll-1`.
  String fileKeyPackage(
      AtKeys keys, ({Uint8List publicKey, Uint8List secretKey}) pair,
      {required DateTime createdAt,
      CryptographicMaterialStatus status =
          CryptographicMaterialStatus.active}) {
    final kpid = PackageKey.computeKid(base64Encode(pair.publicKey));
    for (final (part, bytes) in [
      (CryptographicMaterialRole.publicEncapsulation, pair.publicKey),
      (CryptographicMaterialRole.privateDecapsulation, pair.secretKey),
    ]) {
      keys.addKey(CryptographicMaterial(
          keyId: kpid,
          enrollmentId: 'enroll-1',
          role: part,
          algorithm: CryptographicMaterialAlgorithm.xWing,
          bytes: AtBytes(bytes),
          createdAt: createdAt,
          status: status));
    }
    return kpid;
  }

  test('a keyfile carrying a superseded package keeps it, as retired',
      () async {
    // NOTE: dropping the superseded key on restart would strand every
    // envelope a peer addressed before the rotation, up to envelopeTtl.
    final keys = AtKeys();
    final oldKpid = fileKeyPackage(
        keys, await XWingPureDartAlgo.instance.generateKeyPair(),
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
        status: CryptographicMaterialStatus.retired);
    final newKpid = fileKeyPackage(
        keys, await XWingPureDartAlgo.instance.generateKeyPair(),
        createdAt: DateTime.now().toUtc());

    expect(
        keyPackageMaterials(keys, enrollmentId: 'enroll-1').map((m) => m.keyId),
        [newKpid, oldKpid],
        reason: 'active first, then retired — the keyfile records the status '
            'itself, and AtKeysAssurance already enforces at most one active '
            'publicEncapsulation material per enrollment and algorithm');

    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    final registrant = TestRegistrant(buildMockClient())
      ..directory = FakeEnrollmentDirectory();
    bindKeyPackageToAtKeys(registrant,
        keysIo: io, atSign: atSign, enrollmentId: 'enroll-1');
    final pkg = await registrant.register();

    expect(registrant.kpid, newKpid,
        reason: 'the address is the active key, which is the one the '
            'enrollment record advertises');
    expect(registrant.heldKpids, {newKpid, oldKpid});
    expect(pkg.keys.singleWhere((k) => k.kid == oldKpid).status,
        KeyEntryStatus.retired);
    expect(pkg.keys.singleWhere((k) => k.kid == newKpid).status,
        KeyEntryStatus.active);
  });

  test('a status this build does not know is carried across, not flattened',
      () async {
    // NOTE: both status vocabularies are open, so an unknown token must cross
    // this seam unchanged rather than collapse to `retired`, which is the
    // permissive answer.
    final keys = AtKeys();
    final unknownKpid = fileKeyPackage(
        keys, await XWingPureDartAlgo.instance.generateKeyPair(),
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
        status: CryptographicMaterialStatus.of('revoked'));
    final liveKpid = fileKeyPackage(
        keys, await XWingPureDartAlgo.instance.generateKeyPair(),
        createdAt: DateTime.now().toUtc());

    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    final registrant = TestRegistrant(buildMockClient())
      ..directory = FakeEnrollmentDirectory();
    bindKeyPackageToAtKeys(registrant,
        keysIo: io, atSign: atSign, enrollmentId: 'enroll-1');
    final pkg = await registrant.register();

    expect(registrant.kpid, liveKpid,
        reason: 'the address is still the active key - an unknown status is '
            'never the one advertised');
    expect(pkg.keys.singleWhere((k) => k.kid == unknownKpid).status, 'revoked',
        reason: 'the keyfile token reaches the advertisement unchanged');
    expect(
        pkg.keys
            .singleWhere((k) => k.kid == unknownKpid)
            .offeredForNewOperations,
        isFalse,
        reason: 'and it is not offered for new traffic, which is what the '
            'collapse to `retired` got right and the only thing it did');
  });

  test('a dead key package is not adopted at all', () async {
    // NOTE: status only moves forward and dead is the end of it, so a dead
    // key is neither answered on nor advertised.
    final keys = AtKeys();
    fileKeyPackage(keys, await XWingPureDartAlgo.instance.generateKeyPair(),
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 9)),
        status: CryptographicMaterialStatus.dead);
    final liveKpid = fileKeyPackage(
        keys, await XWingPureDartAlgo.instance.generateKeyPair(),
        createdAt: DateTime.now().toUtc());

    expect(
        keyPackageMaterials(keys, enrollmentId: 'enroll-1').map((m) => m.keyId),
        [liveKpid]);

    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    final registrant = TestRegistrant(buildMockClient())
      ..directory = FakeEnrollmentDirectory();
    bindKeyPackageToAtKeys(registrant,
        keysIo: io, atSign: atSign, enrollmentId: 'enroll-1');
    final pkg = await registrant.register();

    expect(registrant.heldKpids, {liveKpid});
    expect(pkg.keys.map((k) => k.kid), [liveKpid]);
  });

  group('Given an enrollment holding a key package its keyfile does not', () {
    const enrollmentId = 'enroll-1';

    /// A client of the enrollment advertising [algorithms], its registration
    /// bound to its keyfile and registered, so it holds a package in memory
    /// that the keyfile, holding none, does not.
    Future<({MockAtClient client, TestRegistrant holder})> holding(
        {List<String> algorithms = const [SecretSharingAlgos.xWing]}) async {
      final client = buildRemoteBackedMockClient(
          atSign: atSign,
          enrollmentId: enrollmentId,
          remoteData: remoteData,
          keyEstablishmentAlgorithms: algorithms);
      final holder = TestRegistrant(client)
        ..directory = FakeEnrollmentDirectory();
      bindKeyPackageToAtKeys(holder,
          keysIo: client.atKeysIo!, atSign: atSign, enrollmentId: enrollmentId);
      await holder.register();
      return (client: client, holder: holder);
    }

    /// Reconciles [client]'s key package against a record listing none,
    /// recording each package published and what [holder] held as it went
    /// out.
    Future<List<({List<String> advertised, Set<String> held})>> reconcile(
        AtClient client, TestRegistrant holder,
        {FakeEnrollmentDirectory? directory}) async {
      final published = <({List<String> advertised, Set<String> held})>[];
      await KeyPackageMinting(client,
              updater: _RecordingUpdater((request) => published.add((
                    advertised: advertisedKids(request),
                    held: {...holder.heldKpids}
                  ))),
              directory: directory ??
                  (FakeEnrollmentDirectory()..authorize('wavi', enrollmentId)),
              holder: holder)
          .reconcileKeyPackage();
      return published;
    }

    test(
        'when the key package is reconciled, then the one it holds is filed '
        'and advertised, at the kpid it already had', () async {
      final (:client, :holder) = await holding();
      final kpid = holder.kpid;

      final published = await reconcile(client, holder);

      expect(
          published.map((p) => p.advertised),
          [
            [kpid]
          ],
          reason: 'a second package minted here would be advertised while '
              'this client answered at the first');
      expect(holder.kpid, kpid);
      expect(
          keyPackageMaterial(await client.atKeysIo!.read(atSign),
                  enrollmentId: enrollmentId)
              ?.keyId,
          kpid,
          reason: 'filed, so the next start holds it too');
    });

    test(
        'when the preference names a second algorithm, then it holds both '
        'before either is advertised', () async {
      final (:client, :holder) = await holding(algorithms: const [
        SecretSharingAlgos.xWing,
        SecretSharingAlgos.mlKem1024
      ]);
      expect(holder.heldKpids, hasLength(1),
          reason: 'the precondition: registration mints the first only');

      final published = await reconcile(client, holder);

      expect(published, hasLength(1));
      expect(published.single.advertised, hasLength(2));
      expect(published.single.held, published.single.advertised.toSet(),
          reason: 'a key advertised before this client holds it is an '
              'address senders seal to that it cannot open');
    });

    test(
        'when the preference names only an algorithm it holds no key for, then '
        'a fresh key is minted, held and advertised alone', () async {
      final held = await holding();
      final xWingKpid = held.holder.kpid;
      final mlKemOnly = buildRemoteBackedMockClient(
          atSign: atSign,
          enrollmentId: enrollmentId,
          remoteData: remoteData,
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024]);
      when(() => mlKemOnly.atKeysIo).thenReturn(held.client.atKeysIo);

      final published = await reconcile(mlKemOnly, held.holder);

      expect(published, hasLength(1));
      expect(published.single.advertised, hasLength(1));
      expect(published.single.advertised, isNot(contains(xWingKpid)));
      expect(published.single.held, published.single.advertised.toSet(),
          reason: 'the X-Wing key it held was never advertised, so nothing '
              'was sealed to it, and holding it in place of what is '
              'advertised would open nothing sent here');
    });

    test(
        'when it starts again, then it holds the advertised package and '
        'nothing is published', () async {
      final (:client, :holder) = await holding();
      final first = await reconcile(client, holder);
      final directory = FakeEnrollmentDirectory()
        ..authorize('wavi', enrollmentId)
        ..seed(
            enrollmentId,
            KeyPackage(
                enrollmentId: enrollmentId,
                createdAt: DateTime.utc(2026),
                keys: KeyPackageMinting.advertisedKeysIn(
                        await client.atKeysIo!.read(atSign), enrollmentId)
                    .keys));

      final restarted = TestRegistrant(client)
        ..directory = FakeEnrollmentDirectory();
      bindKeyPackageToAtKeys(restarted,
          keysIo: client.atKeysIo!, atSign: atSign, enrollmentId: enrollmentId);
      await restarted.register();
      final again = await reconcile(client, restarted, directory: directory);

      expect(restarted.kpid, first.single.advertised.single);
      expect(again, isEmpty, reason: 'the record already names it');
    });

    test(
        'when it starts again without an algorithm it holds a key for, then '
        'that key is held retired and the other is its kpid', () async {
      final (:client, :holder) = await holding(algorithms: const [
        SecretSharingAlgos.xWing,
        SecretSharingAlgos.mlKem1024
      ]);
      final both = await reconcile(client, holder);
      final xWingKpid = holder.kpid;
      final mlKemKpid =
          both.single.advertised.singleWhere((kid) => kid != xWingKpid);

      final mlKemOnly = buildRemoteBackedMockClient(
          atSign: atSign,
          enrollmentId: enrollmentId,
          remoteData: remoteData,
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024]);
      when(() => mlKemOnly.atKeysIo).thenReturn(client.atKeysIo);
      final restarted = TestRegistrant(mlKemOnly)
        ..directory = FakeEnrollmentDirectory();
      bindKeyPackageToAtKeys(restarted,
          keysIo: client.atKeysIo!, atSign: atSign, enrollmentId: enrollmentId);
      await restarted.register();
      expect(restarted.heldStatuses,
          {xWingKpid: KeyEntryStatus.active, mlKemKpid: KeyEntryStatus.active},
          reason: 'the precondition: both are filed active');

      await reconcile(mlKemOnly, restarted);

      expect(restarted.heldStatuses[xWingKpid], KeyEntryStatus.retired);
      expect(restarted.kpid, mlKemKpid,
          reason: 'the package now advertises the ML-KEM key as its kpid, '
              'and a request sent from the retired one is ignored');
    });
  });
}

/// The kids of the key package [request] advertises.
List<String> advertisedKids(EnrollmentUpdateRequest request) => [
      for (final key in ((SignedEnvelope.fromJson(
                  request.metadata!['keyPackage'] as Map<String, dynamic>)
              .payload as Map)['keys'] as List)
          .cast<Map>())
        key['kid'] as String
    ];

/// Hands each key package update to [onUpdate] instead of sending it.
class _RecordingUpdater extends Fake implements EnrollmentUpdater {
  _RecordingUpdater(this.onUpdate);

  final void Function(EnrollmentUpdateRequest request) onUpdate;

  @override
  Future<AtEnrollmentResponse> update(
      EnrollmentUpdateRequest request, AtLookUp atLookUp) async {
    onUpdate(request);
    return AtEnrollmentResponse(
        request.enrollmentId, EnrollmentStatus.approved);
  }
}
