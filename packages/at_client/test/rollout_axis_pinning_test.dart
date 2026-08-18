import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// A client that already exists keeps the rollout axes it was built under, and
/// a caller handing over different ones is refused rather than ignored.
///
/// Every axis here is final at construction — what a client writes must not
/// change meaning mid-run — so a second preference naming a different one
/// cannot be adopted. The only choice is between refusing and dropping it, and
/// dropping it is what this used to do. After the auth/signing split that is
/// not a flag being ignored: the stage decides which algorithm an enrollment
/// authenticates with and which signing key it holds, so the caller runs on
/// the wrong **key** and learns about it when a peer cannot verify it.
///
/// ⚠️ **Two paths hand back a client that already exists, and only one is the
/// cache.** `AtClientManager.setCurrentAtSign` short-circuits on a same-atSign
/// call carrying no override argument and returns without calling
/// `AtClientImpl.create` at all — which is the ordinary path, so a guard on
/// the cache alone would be loud where a caller passes an override and silent
/// everywhere else.
void main() {
  const atSign = '@alice';

  AtClientPreference preference(
          {PqPosture? posture,
          SigningRollout? signingRollout,
          Set<SigningAlgoType>? inUseSigningAlgorithms,
          bool? disallowLegacyEncryption}) =>
      AtClientPreference(
          posture: posture ?? const PqPosture.migration(),
          signingRollout: signingRollout,
          inUseSigningAlgorithms: inUseSigningAlgorithms,
          disallowLegacyEncryption: disallowLegacyEncryption)
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';

  group('what counts as the same settings', () {
    test('two separately built default preferences are interchangeable', () {
      // The case that decides the whole design. Callers hand over a FRESH
      // preference object on every call — the e2e pack builds one per
      // setCurrentAtSign — so an identity comparison would refuse every one
      // of them, and this guard would be a break rather than a check.
      expect(preference().rolloutDifferencesFrom(preference()), isEmpty);
    });

    test('a posture built without const is still the same posture', () {
      // PqPosture declares no ==, so comparing two of them compares
      // identity, and only const instances are canonicalized. Comparing the
      // posture as an object would make this pair a mismatch, on a difference
      // that does not exist.
      final canonical = preference(posture: const PqPosture.migration());
      // ignore: prefer_const_constructors
      final built = preference(posture: PqPosture.migration());

      expect(identical(canonical.posture, built.posture), isFalse,
          reason: 'the control: if these were the same instance the row below '
              'would pass for a build that compares identity, and would be '
              'proving nothing');
      expect(canonical.rolloutDifferencesFrom(built), isEmpty);
    });

    test('the same set built in a different order is the same set', () {
      final one = preference(inUseSigningAlgorithms: const {
        SigningAlgoType.mldsa65,
        SigningAlgoType.rsa2048
      });
      final other = preference(inUseSigningAlgorithms: const {
        SigningAlgoType.rsa2048,
        SigningAlgoType.mldsa65
      });

      expect(one.rolloutDifferencesFrom(other), isEmpty,
          reason: 'membership is the whole of the meaning — a Set iterates in '
              'insertion order, and comparing that would refuse two identical '
              'clients');
    });

    test('crypto and everything outside the rollout axes are not compared', () {
      final one = preference()..syncBatchSize = 5;
      final other = preference()
        ..syncBatchSize = 500
        ..crypto = CryptoConfig.legacy();

      expect(one.rolloutDifferencesFrom(other), isEmpty,
          reason: 'crypto is adopted by a re-used client rather than refused, '
              'so that a provider registered after first construction takes '
              'effect');
    });
  });

  group('what counts as different settings', () {
    test('an axis that moves alone is reported alone', () {
      final now = preference();

      expect(
          now.rolloutDifferencesFrom(
              preference(disallowLegacyEncryption: true)),
          [contains('disallowLegacyEncryption')]);
      expect(
          now.rolloutDifferencesFrom(preference(
              inUseSigningAlgorithms: const {SigningAlgoType.rsa2048})),
          [contains('inUseSigningAlgorithms')]);
    });

    test('naming a stage moves the set it derives, and both are reported', () {
      // Not two mistakes but one: the in-use set defaults from the stage, so a
      // caller that names only signingRollout has changed two axes. A
      // diagnostic naming just the one it was handed would send a reader
      // looking for a second setting nobody wrote.
      expect(
          preference().rolloutDifferencesFrom(
              preference(signingRollout: SigningRollout.rollout1)),
          [
            'signingRollout (asked rollout1, running now)',
            'inUseSigningAlgorithms (asked {rsa2048}, running {})',
          ]);
    });

    test('a posture difference is named by what it means', () {
      // The posture is compared through the two fields nothing else carries.
      // Its other axes reach behaviour as signingRollout and
      // disallowLegacyEncryption, which is why they are listed beside it
      // rather than instead of it.
      final differences = preference()
          .rolloutDifferencesFrom(
              preference(posture: const PqPosture.postQuantum()));

      expect(
          differences,
          containsAll([
            contains('posture.writesPqByDefault'),
            contains('posture.keyExchangeMode'),
            contains('signingRollout'),
            contains('disallowLegacyEncryption'),
            contains('inUseSigningAlgorithms'),
          ]),
          reason: 'one posture moves five axes, and a diagnostic naming only '
              'the first would send a reader looking for one setting');
    });

    test('the difference reads as asked-versus-running', () {
      final running = preference();
      final asked = preference(disallowLegacyEncryption: true);

      expect(running.rolloutDifferencesFrom(asked).single,
          'disallowLegacyEncryption (asked true, running false)',
          reason: 'the caller is the one holding a preference it expected to '
              'take effect, so the message states its side first');
    });

    test('a mixture of posture and explicit axis compares the effective value',
        () {
      // signingRollout given explicitly beats the posture's, which is the
      // documented contract. So these two agree on the stage and differ only
      // on what the posture itself carries.
      final postured = preference(
          posture: const PqPosture.postQuantum(),
          signingRollout: SigningRollout.now,
          inUseSigningAlgorithms: const {});
      final plain = preference(signingRollout: SigningRollout.now);

      final differences = postured.rolloutDifferencesFrom(plain);
      expect(differences.any((d) => d.contains('signingRollout')), isFalse,
          reason: 'the effective stage is the same on both sides');
      expect(
          differences,
          containsAll([
            contains('posture.writesPqByDefault'),
            contains('disallowLegacyEncryption'),
          ]));
    });
  });

  group('the refusal a caller meets', () {
    setUp(() => AtClientImpl.atClientInstanceMap.remove(atSign));
    tearDown(() => AtClientImpl.atClientInstanceMap.remove(atSign));

    test('names the axis, the client and what to do about it', () {
      expect(
          () => AtClientImpl.refuseChangedRolloutAxes(
              running: preference(),
              asked: preference(signingRollout: SigningRollout.rollout1),
              cacheKey: '$atSign|enroll-a'),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', allOf(
                  contains('signingRollout'),
                  contains('$atSign|enroll-a'),
                  contains('final at construction')))));
    });

    test('says nothing when the settings agree', () {
      expect(
          () => AtClientImpl.refuseChangedRolloutAxes(
              running: preference(),
              asked: preference(),
              cacheKey: atSign),
          returnsNormally);
    });

    test('and the cache actually asks it', () async {
      // The guard existing is not the guard running. What makes this row worth
      // its cost is that it drives AtClientImpl.create twice, which is the
      // production path a second AtClientManager takes.
      final first = await AtClientImpl.create(atSign, 'wavi', preference());

      await expectLater(
          AtClientImpl.create(atSign, 'wavi',
              preference(signingRollout: SigningRollout.rollout1)),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('signingRollout'))));

      // The control, on the same cached client: an equal preference is handed
      // back the client that already exists. Without this the row above passes
      // for a build that refuses every second create.
      expect(identical(await AtClientImpl.create(atSign, 'wavi', preference()),
              first),
          isTrue);
    });

    test('and the manager\'s same-atSign short-circuit asks it too', () async {
      // The path the plan row did not name, and the ordinary one: with no
      // override argument setCurrentAtSign returns the client it already has
      // WITHOUT calling create, so a guard on the cache alone never runs here.
      // A throw is therefore proof that this second site fired — nothing else
      // on this path can raise one.
      final manager = AtClientManager(atSign);
      await manager.setCurrentAtSign(atSign, 'wavi', preference());

      await expectLater(
          manager.setCurrentAtSign(
              atSign, 'wavi', preference(disallowLegacyEncryption: true)),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', contains('disallowLegacyEncryption'))));

      await manager.setCurrentAtSign(atSign, 'wavi', preference());
    });

    test('and so does setPreferences, which names its replacement', () async {
      // The third door, and the one that would have made the other two a
      // check in appearance only: naming the replacement does not make the
      // change possible, because the substrate read these axes at a startup
      // that has already run. Accepting them would leave the client REPORTING
      // a stage it never applied.
      final client = await AtClientImpl.create(atSign, 'wavi', preference());

      expect(
          () => client.setPreferences(
              preference(inUseSigningAlgorithms: const {SigningAlgoType.mldsa65})),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', contains('inUseSigningAlgorithms'))));

      // The control: everything outside the rollout axes is still replaced,
      // which is what this method is for.
      client.setPreferences(preference()..syncBatchSize = 42);
      expect(client.getPreferences()!.syncBatchSize, 42);
    });

    test('a client with no preference at all is not refused', () {
      // Nothing to disagree with. Refusing here would turn "this client has
      // not finished being built" into a stage mismatch, which is a different
      // failure with a much more misleading message.
      expect(
          () => AtClientImpl.refuseChangedRolloutAxes(
              running: null,
              asked: preference(posture: const PqPosture.postQuantum()),
              cacheKey: atSign),
          returnsNormally);
    });
  });
}
