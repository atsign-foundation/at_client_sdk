import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/crypto/nskey/pre_publish_conveyance.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';
import 'test_utils/recorded_logs.dart';

class MockAtClient extends Mock implements AtClient {}

class MockSharing extends Mock implements PairwiseSecretSharing {}

class FakeSecret extends Fake implements Secret {}

/// What a mint conveys before it publishes, and who may mint at all.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.7
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';
  final logs = RecordedLogs();

  setUpAll(() {
    logs.installOn();
    registerFallbackValue(FakeSecret());
  });

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
        'when its kids reach different numbers of key packages, then pushedTo '
        'is the fewest', () async {
      final s = substrate(directory, 'e1');
      // NOTE: the fewest is neither first nor last, so keeping either, or the
      // most, gives another answer.
      final reached = {'__nskey.k1': 3, '__nskey.k2': 1, '__nskey.k3': 2};
      when(() => s.sharing.pushSecretToNamespaceMembers(any(),
              excludeEnrollmentIds: any(named: 'excludeEnrollmentIds')))
          .thenAnswer((inv) async =>
              reached[(inv.positionalArguments.first as Secret).name]!);
      final conveyance = (await PrePublishConveyance.prepare(
          s.sharing, await filingHolding(['k1', 'k2', 'k3']), namespace))!;

      await conveyance.convey(['k1', 'k2', 'k3']);

      expect(conveyance.pushedTo, 1,
          reason: 'a key package that holds one kid of a generation and not '
              'the other cannot open everything sealed to it');
    });

    test(
        'when the lock is sized, then it is the margin plus the budget for '
        'each listed enrollment, kid and conveyance, and never past the '
        'atServer\'s limit', () async {
      final s = substrate(directory, 'e1');
      final conveyance = (await PrePublishConveyance.prepare(
          s.sharing, await filingHolding([]), namespace))!;

      expect(
          conveyance.lockTtlFor(
              margin: const Duration(minutes: 2),
              perMember: const Duration(seconds: 2),
              kids: 2,
              conveyances: 2),
          const Duration(minutes: 2, seconds: 24),
          reason: 'three enrollments are listed (e1, e2 and primary), each '
              'pushed two kids, by the mint and by the rotation its '
              'afterPublish may make');
      expect(
          conveyance.lockTtlFor(
              margin: const Duration(minutes: 2),
              perMember: const Duration(seconds: 2),
              kids: 1,
              conveyances: 1),
          const Duration(minutes: 2, seconds: 6),
          reason: 'the control: one kid in one conveyance is the budget per '
              'listed enrollment');
      expect(
          conveyance.lockTtlFor(
              margin: const Duration(minutes: 14),
              perMember: const Duration(minutes: 1),
              kids: 1,
              conveyances: 1),
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
          reason: 'what it filed is retired, so the next mint is a fresh '
              'one');
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

    group('and a generation it conveyed and published', () {
      late NskeyPrivateFiling filing;
      late ({MockSharing sharing, List<String> pushed}) s;
      late PrePublishConveyance conveyance;
      late NskeyAdvertisement published;
      late NskeyAdvertisement successor;
      late List<String> rotations;

      /// A rotation under the held lock, as the ring hands it: it files the
      /// successor, conveys it through what it is given, and then runs the
      /// after-publish it is given.
      NskeyRotateHoldingLease rotateTo(NskeyAdvertisement next,
              {Object? failWith}) =>
          ({conveyFirst, afterPublish}) async {
            rotations.add(next.nskeyKid);
            if (failWith != null) throw failWith;
            await conveyFirst?.call([next.nskeyKid]);
            await afterPublish?.call(next);
            return next;
          };

      setUp(() async {
        s = substrate(directory, 'e1');
        final first = await _generation();
        final second = await _generation();
        published = first.advertisement;
        successor = second.advertisement;
        filing = await filingHolding([]);
        await filing.store(
            namespace: namespace, nskeyKid: first.kid, seed: first.seed);
        await filing.store(
            namespace: namespace, nskeyKid: second.kid, seed: second.seed);
        conveyance =
            (await PrePublishConveyance.prepare(s.sharing, filing, namespace))!;
        await conveyance.convey([first.kid]);
        rotations = [];
      });

      test(
          'when a revocation touches the namespace after the conveyance read '
          'it, then the keyfile records that the generation owes a rotation, '
          'and it is rotated onto a successor conveyed afresh', () async {
        directory.revoke('e2', at: DateTime.utc(2026, 10, 29));

        final next =
            await conveyance.afterPublish(published, rotateTo(successor));

        expect(next, successor);
        expect(rotations, [successor.nskeyKid]);
        expect(
            await filing.rotationOwed(namespace, [published.nskeyKid]), isTrue,
            reason: 'recorded before the rotation, so a rotation that fails '
                'is owed at the next start');
        expect(s.pushed.last, '__nskey.${successor.nskeyKid}');
        expect(conveyance.conveyedKids, contains(successor.nskeyKid));
        expect(
            await filing.rotationOwed(namespace, [successor.nskeyKid]), isFalse,
            reason: 'the successor was conveyed to the roster as it is now');
      });

      Iterable<String> severe() =>
          logs.at('SEVERE').where((m) => m.contains('left to the next start'));

      test(
          'when the rotation fails, then the generation published stands, the '
          'record stays, and the failure is logged at severe', () async {
        directory.revoke('e2', at: DateTime.utc(2026, 10, 29));
        logs.records.clear();

        expect(
            await conveyance.afterPublish(published,
                rotateTo(successor, failWith: StateError('lease spent'))),
            isNull,
            reason: 'the publish has happened, so a failure after it must not '
                'read as the mint failing');
        expect(
            await filing.rotationOwed(namespace, [published.nskeyKid]), isTrue);
        expect(severe().single,
            allOf(contains(namespace), contains('lease spent')));
      });

      test(
          'when this enrollment no longer carries a key package to convey a '
          'successor with, then the generation published stands and the '
          'failure is logged at severe', () async {
        directory
          ..revoke('e2', at: DateTime.utc(2026, 10, 29))
          ..rejected.add('e1');
        logs.records.clear();

        expect(await conveyance.afterPublish(published, rotateTo(successor)),
            isNull);
        expect(rotations, isEmpty);
        expect(
            await filing.rotationOwed(namespace, [published.nskeyKid]), isTrue);
        expect(severe().single,
            allOf(contains(namespace), contains('no longer carries a key')));
      });

      test(
          'when no revocation touches it, then nothing is recorded and nothing '
          'rotates — the control', () async {
        expect(await conveyance.afterPublish(published, rotateTo(successor)),
            isNull);
        expect(rotations, isEmpty);
        expect(await filing.rotationOwed(namespace, [published.nskeyKid]),
            isFalse);
      });
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

    test(
        'when it seeds with no substrate at all, then it answers cannotConvey '
        'and mints nothing', () async {
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
          NskeySeedOutcome.cannotConvey,
          reason: 'a missing substrate is not a missing key package, and '
              'reporting it as one sends the caller to the wrong fix');
      expect(ring.mints, 0);
    });
  });
}

/// A fresh X-Wing generation: its kid, the seed filed for it, and the
/// advertisement naming it.
Future<({String kid, NskeySeed seed, NskeyAdvertisement advertisement})>
    _generation() async {
  final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
  final seed = kem.newSeed();
  final pair = await kem.keyPairFromSeed(seed);
  final advertisement = NskeyAdvertisement.single(
      publicKey: pair.publicKey, alg: SecretSharingAlgos.xWing);
  return (
    kid: advertisement.nskeyKid,
    seed: NskeySeed(seed),
    advertisement: advertisement
  );
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
      NskeyAfterPublish? afterPublish,
      Duration? lockTtl}) async {
    mints++;
    throw StateError('a mint was asked of a client that may mint nothing');
  }
}
