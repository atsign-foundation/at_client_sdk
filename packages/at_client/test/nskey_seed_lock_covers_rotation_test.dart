import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';
import 'test_utils/mocks.dart';

class MockSharing extends Mock implements PairwiseSecretSharing {}

/// The mint lock a seed takes, sized for the conveyances it may make while
/// holding it.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.7
void main() {
  const atSign = '@alice';
  const unpublished = 'app_1.my_apps';
  const published = 'app_2.my_apps';
  const listed = ['e1', 'e2', 'e3'];

  late MockAtClient atClient;
  late _RecordingRing ring;
  late NskeySeeding seeding;

  setUp(() async {
    atClient = MockAtClient(keyEstablishmentAlgorithms: const [
      SecretSharingAlgos.xWing,
      SecretSharingAlgos.mlKem1024,
    ]);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn(listed.first);

    final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
    final directory = FakeEnrollmentDirectory();
    for (final enrollmentId in listed) {
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      directory
        ..authorize(unpublished, enrollmentId)
        ..authorize(published, enrollmentId)
        ..seed(
            enrollmentId,
            KeyPackage(
                enrollmentId: enrollmentId,
                createdAt: DateTime.utc(2026),
                keys: [
                  PackageKey.fromBytes(
                      use: SecretSharingAlgos.useEnc,
                      alg: SecretSharingAlgos.xWing,
                      pub: pair.publicKey)
                ]));
    }
    final sharing = MockSharing();
    when(() => sharing.directory).thenReturn(directory);
    when(() => sharing.enrollmentId).thenReturn(listed.first);
    when(() => sharing.secretStore).thenReturn(SecretStore());

    ring = _RecordingRing(atClient, published: {
      published: NskeyAdvertisement.single(
        publicKey: Uint8List.fromList(List<int>.filled(1216, 7)),
        alg: SecretSharingAlgos.xWing,
        createdAt: DateTime.now().toUtc(),
      ),
    });
    seeding = NskeySeeding(
      atClient: atClient,
      ring: ring,
      sharing: sharing,
      privateFiling:
          NskeyPrivateFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign),
    );
  });

  /// The lock budget for one conveyance of [kids] to every listed enrollment.
  Duration oneConveyance(int kids) =>
      ring.lockBudgetPerMember * (listed.length * kids);

  group(
      'UC-A3.7 · Given three enrollments listed with verified key packages for '
      'a namespace with nothing published', () {
    test(
        'when a client seeds it, then the mint lock lasts for two conveyances '
        'to the roster: the mint\'s own and a rotation\'s under the same lock',
        () async {
      final kids = ring.wantedKeyAlgorithms().length;
      final twice = ring.lockTtl + oneConveyance(kids) * 2;
      expect(twice, lessThan(maxServerMutexTtl),
          reason: 'the premise: the atServer\'s limit does not cap the ttl, '
              'so one conveyance and two are different ttls');

      await seeding.seedNamespace(atSign, unpublished);

      expect(ring.mintLockTtls, {unpublished: twice},
          reason: 'a seed that mints takes its lock for its own conveyance '
              'and for the one a rotation in afterPublish makes while the '
              'lock is still held, each of every kid to every listed '
              'enrollment');
    });
  });

  group(
      'Given a namespace whose published generation lacks one of this '
      'client\'s algorithms', () {
    test('when a client seeds it, then the add locks for one conveyance',
        () async {
      await seeding.seedNamespace(atSign, published, askRotationPolicy: false);

      expect(ring.addLockTtls, {published: ring.lockTtl + oneConveyance(1)},
          reason: 'the control: an add conveys once, so its lock is sized '
              'for one conveyance of the kid it adds, and the recorder tells '
              'one conveyance from two');
      expect(ring.mintLockTtls, isEmpty);
    });
  });
}

/// A ring that answers [published] for what the atServer holds, and records
/// the lock ttl each mint and each add is handed instead of taking a lock.
class _RecordingRing extends PublishedNskeyKeyRing {
  _RecordingRing(super.atClient, {required this.published});

  final Map<String, NskeyAdvertisement> published;

  final Map<String, Duration?> mintLockTtls = {};
  final Map<String, Duration?> addLockTtls = {};

  @override
  Future<({NskeyAdvertisement advertisement, DateTime? updatedAt})?>
      publishedRecord(String owner, String namespace) async {
    final advertisement = published[namespace];
    return advertisement == null
        ? null
        : (advertisement: advertisement, updatedAt: null);
  }

  @override
  List<String> missingKeyAlgorithms(NskeyAdvertisement current) =>
      const [SecretSharingAlgos.mlKem1024];

  @override
  Future<NskeyAdvertisement> mintAndPublish(String namespace,
      {Future<void> Function(List<String> nskeyKids)? conveyFirst,
      NskeyAfterPublish? afterPublish,
      Duration? lockTtl}) async {
    mintLockTtls[namespace] = lockTtl;
    return NskeyAdvertisement.single(
      publicKey: Uint8List.fromList(List<int>.filled(1216, 9)),
      alg: SecretSharingAlgos.xWing,
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<NskeyAdvertisement?> add(String namespace,
      {Future<void> Function(List<String> nskeyKids)? conveyFirst,
      Duration? lockTtl}) async {
    addLockTtls[namespace] = lockTtl;
    return null;
  }
}
