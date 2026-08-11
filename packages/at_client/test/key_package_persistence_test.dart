import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/secret_sharing/key_package_persistence.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

import 'fake_enrollment_directory.dart';

class TestRegistrant
    with ApkamSigning, EnvelopeSigning, KeyPackageRegistration {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestRegistrant');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;

  TestRegistrant(this.atClient);
}

/// Backing the registration mixin's enc keypair with the keyfile.
///
/// A sender addresses an envelope to the `kpid` it read from the enrollment
/// record, so a client whose kpid moves between processes scans for an address
/// nobody writes to and can never be sent anything. That is not a degraded
/// mode — it is the difference between the substrate delivering key material
/// and delivering none.
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

  /// The keyfile an enrollment made with `enrollmentKeyPackageBuilder` carries:
  /// both halves of one X-Wing keypair, filed under the kpid they address.
  Future<(InMemoryAtKeysIo, String)> keyfileWithPackage() async {
    final pair = await XWingPureDartAlgo.instance.generateKeyPair();
    final kpid = PackageKey.computeKid(base64Encode(pair.publicKey));
    final keys = AtKeys();
    final now = DateTime.now().toUtc();
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.publicEncapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(pair.publicKey),
      createdAt: now,
    ));
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.privateDecapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
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

  test('a filed nskey private is never adopted as the key package', () async {
    final (io, advertised) = await keyfileWithPackage();
    // Conveyed later, so it sorts newest — the trap a createdAt-only rule
    // would fall into.
    await NskeyPrivateFiling(keysIo: io, atSign: atSign).file(Secret(
      namespace: 'app_1.my_apps',
      name: '${NskeyPrivateFiling.secretNamePrefix}kid-one',
      value: base64Encode(Uint8List.fromList(List<int>.generate(64, (i) => i))),
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
      value: base64Encode(Uint8List.fromList(List<int>.generate(64, (i) => i))),
    ));

    expect(keyPackageMaterial(await io.read(atSign)), isNull,
        reason: 'an nskey private arrives alone — its public half is published '
            'on the atServer, not kept here, and that is what tells the two '
            'apart');
  });

  test(
      'a retrofitted keyfile: each principal adopts its OWN package, never '
      'its co-tenant\'s', () async {
    // The shape a self-retrofit leaves behind: the legacy enrollment's
    // package untagged (filed before materials carried enrollment ids) and
    // the PQ enrollment's tagged with its id — the tagged one newer.
    final keys = AtKeys();
    final legacyPair = await XWingPureDartAlgo.instance.generateKeyPair();
    final legacyKpid = PackageKey.computeKid(base64Encode(legacyPair.publicKey));
    final pqPair = await XWingPureDartAlgo.instance.generateKeyPair();
    final pqKpid = PackageKey.computeKid(base64Encode(pqPair.publicKey));
    final older = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final newer = DateTime.now().toUtc();
    for (final (kpid, pair, id, at) in [
      (legacyKpid, legacyPair, null, older),
      (pqKpid, pqPair, 'pq-enrollment-1', newer),
    ]) {
      keys.addKey(AtKeysMaterial(
          keyId: kpid,
          enrollmentId: id,
          keyPartType: CryptographicKeyType.publicEncapsulation,
          keyAlgorithmType: KeyAlgorithmType.xWing,
          bytes: AtBytes(pair.publicKey),
          createdAt: at));
      keys.addKey(AtKeysMaterial(
          keyId: kpid,
          enrollmentId: id,
          keyPartType: CryptographicKeyType.privateDecapsulation,
          keyAlgorithmType: KeyAlgorithmType.xWing,
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
  });
}
