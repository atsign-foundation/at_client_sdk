import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/crypto/nskey/pre_publish_conveyance.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';

class MockAtClient extends Mock implements AtClient {}

class MockSharing extends Mock implements PairwiseSecretSharing {}

class FakeSecret extends Fake implements Secret {}

/// What a mint conveys before it publishes, and who may mint at all.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.7
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() => registerFallbackValue(FakeSecret()));

  Future<KeyPackage> keyPackage(String enrollmentId) async {
    final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
    final pair = await kem.keyPairFromSeed(kem.newSeed());
    return KeyPackage(
        enrollmentId: enrollmentId,
        createdAt: DateTime.utc(2026),
        keys: [
          PackageKey.fromBytes(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.xWing,
              pub: pair.publicKey)
        ]);
  }

  /// A substrate over [directory] for enrollment [self], recording each push.
  ({MockSharing sharing, List<String> pushed}) substrate(
      FakeEnrollmentDirectory directory, String self) {
    final sharing = MockSharing();
    final pushed = <String>[];
    when(() => sharing.directory).thenReturn(directory);
    when(() => sharing.enrollmentId).thenReturn(self);
    when(() => sharing.secretStore).thenReturn(SecretStore());
    when(() => sharing.pushSecretToNamespaceMembers(any(),
            excludeEnrollmentIds: any(named: 'excludeEnrollmentIds')))
        .thenAnswer((inv) async {
      pushed.add((inv.positionalArguments.first as Secret).name);
      return 1;
    });
    return (sharing: sharing, pushed: pushed);
  }

  Future<NskeyPrivateFiling> filingHolding(List<String> kids) async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final filing = NskeyPrivateFiling(keysIo: io, atSign: atSign);
    for (final kid in kids) {
      await filing.store(
          namespace: namespace,
          nskeyKid: kid,
          seed: NskeySeed(Uint8List.fromList(List<int>.filled(32, 7))));
    }
    return filing;
  }

  group('Given a minter whose own entry carries a verified key package', () {
    late FakeEnrollmentDirectory directory;

    setUp(() async {
      directory = FakeEnrollmentDirectory()
        ..authorize(namespace, 'e1')
        ..authorize(namespace, 'e2')
        ..authorize(namespace, 'primary')
        ..seed('e1', await keyPackage('e1'))
        ..seed('e2', await keyPackage('e2'));
    });

    test('when it conveys, then every kid is pushed before anything returns',
        () async {
      final s = substrate(directory, 'e1');
      final conveyance = (await PrePublishConveyance.prepare(
          s.sharing, await filingHolding(['k1', 'k2']), namespace))!;

      await conveyance.convey(['k1', 'k2']);

      expect(s.pushed, ['__nskey.k1', '__nskey.k2']);
      expect(conveyance.conveyedKids, {'k1', 'k2'});
    });

    test(
        'when the lock is sized, then it is the margin plus the budget for '
        'each listed enrollment, and never past the atServer\'s limit',
        () async {
      final s = substrate(directory, 'e1');
      final conveyance = (await PrePublishConveyance.prepare(
          s.sharing, await filingHolding([]), namespace))!;

      expect(
          conveyance.lockTtlFor(
              margin: const Duration(minutes: 2),
              perMember: const Duration(seconds: 2)),
          const Duration(minutes: 2, seconds: 6),
          reason: 'three enrollments are listed: e1, e2 and primary');
      expect(
          conveyance.lockTtlFor(
              margin: const Duration(minutes: 14),
              perMember: const Duration(minutes: 1)),
          const Duration(minutes: 15));
    });

    test(
        'when a revocation touches the namespace during the conveyance, then '
        'the publish is refused and what it filed is retired', () async {
      final s = substrate(directory, 'e1');
      final filing = await filingHolding(['k1']);
      final conveyance =
          (await PrePublishConveyance.prepare(s.sharing, filing, namespace))!;
      directory.revoke('e2', at: DateTime.utc(2026, 10, 29));

      await expectLater(
          conveyance.convey(['k1']),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('is not published and is retired'))));
      expect(await filing.filedFor(namespace), isEmpty,
          reason: 'a later mint must not resume a generation the revoked '
              'enrollment may hold');
    });

    test(
        'when no revocation touches it, then the conveyance completes — the '
        'control', () async {
      final s = substrate(directory, 'e1');
      final filing = await filingHolding(['k1']);
      final conveyance =
          (await PrePublishConveyance.prepare(s.sharing, filing, namespace))!;

      await conveyance.convey(['k1']);
      expect(await filing.filedFor(namespace), hasLength(1));
    });
  });

  group('Given a minter whose own entry carries no key package', () {
    test('when it prepares, then it may mint nothing', () async {
      final directory = FakeEnrollmentDirectory()
        ..authorize(namespace, 'primary')
        ..authorize(namespace, 'e1')
        ..seed('e1', await keyPackage('e1'));
      final s = substrate(directory, 'primary');

      expect(
          await PrePublishConveyance.prepare(
              s.sharing, await filingHolding([]), namespace),
          isNull);
    });

    test('when it seeds, then it answers noKeyPackage and mints nothing',
        () async {
      final directory = FakeEnrollmentDirectory()
        ..authorize(namespace, 'primary');
      final s = substrate(directory, 'primary');
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
      final ring = _RingPublishingNothing(atClient);

      final outcome = await NskeySeeding(
              atClient: atClient,
              ring: ring,
              sharing: s.sharing,
              privateFiling: await filingHolding([]))
          .seedNamespace(atSign, namespace);

      expect(outcome, NskeySeedOutcome.noKeyPackage);
      expect(ring.mints, 0);
    });

    test('when it seeds with no substrate at all, then it mints nothing',
        () async {
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
      final ring = _RingPublishingNothing(atClient);

      expect(
          await NskeySeeding(
                  atClient: atClient,
                  ring: ring,
                  privateFiling: await filingHolding([]))
              .seedNamespace(atSign, namespace),
          NskeySeedOutcome.noKeyPackage);
      expect(ring.mints, 0);
    });
  });
}

/// A ring with nothing published that counts the mints asked of it.
class _RingPublishingNothing extends PublishedNskeyKeyRing {
  _RingPublishingNothing(super.atClient);

  int mints = 0;

  @override
  Future<NskeyAdvertisement?> publishedAdvertisement(
          String owner, String namespace) async =>
      null;

  @override
  Future<NskeyAdvertisement> mintAndPublish(String namespace,
      {Future<void> Function(List<String> nskeyKids)? conveyFirst,
      Duration? lockTtl}) async {
    mints++;
    throw StateError('a mint was asked of a client that may mint nothing');
  }
}
