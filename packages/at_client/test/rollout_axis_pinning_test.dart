import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
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
          SigningAlgoType? authenticationKeyAlgorithm,
          Set<SigningAlgoType>? dataSigningKeyAlgorithms}) =>
      AtClientPreference(
          posture: posture ?? PqPosture.legacy,
          authenticationKeyAlgorithm: authenticationKeyAlgorithm,
          dataSigningKeyAlgorithms: dataSigningKeyAlgorithms)
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';

  /// The smallest posture that refuses legacy writes.
  ///
  /// It cannot be "the default with one flag flipped": `PqPosture` rejects
  /// refusing legacy writes while still writing legacy by default, so
  /// `writesPqByDefault` moves with it **by construction**. That is why the
  /// rows below never expect this axis to be reported alone.
  final strict = PqPosture(
    authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
    dataSigningKeyAlgorithms: const {},
    seedNamespaceKeys: false,
    keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
    writesPqByDefault: true,
    disallowLegacyEncryption: true,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
  );

  group('what counts as the same settings', () {
    test('two separately built default preferences are interchangeable', () {
      // The case that decides the whole design. Callers hand over a FRESH
      // preference object on every call — the e2e pack builds one per
      // setCurrentAtSign — so an identity comparison would refuse every one
      // of them, and this guard would be a break rather than a check.
      expect(preference().rolloutDifferencesFrom(preference()), isEmpty);
    });

    test('a hand-built posture equal to a constant is the same posture', () {
      // PqPosture declares no ==, so comparing two of them compares identity,
      // and a program that builds its own posture gets an instance that is
      // not one of the three constants. Comparing the posture as an object
      // would make this pair a mismatch, on a difference that does not exist.
      final canonical = preference(posture: PqPosture.legacy);
      final built = preference(
          posture: PqPosture(
        authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
        dataSigningKeyAlgorithms: const {},
        seedNamespaceKeys: false,
        keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
        writesPqByDefault: false,
        disallowLegacyEncryption: false,
        mintLegacyMaterial: true,
        sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
        keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
      ));

      expect(identical(canonical.posture, built.posture), isFalse,
          reason: 'the control: if these were the same instance the row below '
              'would pass for a build that compares identity, and would be '
              'proving nothing');
      expect(canonical.rolloutDifferencesFrom(built), isEmpty);
    });

    test('the same set built in a different order is the same set', () {
      final one = preference(dataSigningKeyAlgorithms: const {
        SigningAlgoType.mldsa65,
        SigningAlgoType.rsa2048
      });
      final other = preference(dataSigningKeyAlgorithms: const {
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
          now.rolloutDifferencesFrom(preference(
              dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})),
          [contains('dataSigningKeyAlgorithms')]);
      expect(
          now.rolloutDifferencesFrom(
              preference(authenticationKeyAlgorithm: SigningAlgoType.mldsa65)),
          [contains('authenticationKeyAlgorithm')]);
    });

    test('the refusal never moves alone, and both halves are reported', () {
      // Not two mistakes but one. `disallowLegacyEncryption` is posture-only
      // and coupled to `writesPqByDefault`, so a diagnostic naming just the
      // refusal would send a reader looking for a setting nobody could have
      // written on its own.
      expect(
          preference().rolloutDifferencesFrom(preference(posture: strict)),
          containsAll([
            contains('posture.writesPqByDefault'),
            contains('disallowLegacyEncryption'),
          ]));
    });

    test('the two key axes move independently, and are reported that way', () {
      // They were one enum until ruling 113, and pqReady is the stage that
      // exists precisely because they must not move together. A caller naming
      // the authentication algorithm alone has changed ONE axis, and a
      // diagnostic that also named the signing set would send a reader looking
      // for a setting nobody wrote.
      expect(
          preference().rolloutDifferencesFrom(
              preference(authenticationKeyAlgorithm: SigningAlgoType.mldsa65)),
          ['authenticationKeyAlgorithm (asked mldsa65, running rsa2048)']);
      expect(
          preference().rolloutDifferencesFrom(preference(
              dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})),
          ['dataSigningKeyAlgorithms (asked {rsa2048}, running {})']);
    });

    test('a posture difference is named by what it means', () {
      // The posture is compared through the two fields nothing else carries.
      // Its other axes reach behaviour as authenticationKeyAlgorithm,
      // dataSigningKeyAlgorithms and disallowLegacyEncryption, which is why
      // they are listed beside it rather than instead of it.
      final differences = preference()
          .rolloutDifferencesFrom(preference(posture: PqPosture.pqActive));

      expect(
          differences,
          containsAll([
            contains('posture.writesPqByDefault'),
            contains('posture.keyExchangeMode'),
            contains('authenticationKeyAlgorithm'),
            contains('disallowLegacyEncryption'),
            contains('dataSigningKeyAlgorithms'),
          ]),
          reason: 'one posture moves five compared axes, and a diagnostic '
              'naming only the first would send a reader looking for one '
              'setting');
    });

    test('the difference reads as asked-versus-running', () {
      final running = preference();
      final asked = preference(authenticationKeyAlgorithm: SigningAlgoType.mldsa65);

      expect(running.rolloutDifferencesFrom(asked).single,
          'authenticationKeyAlgorithm (asked mldsa65, running rsa2048)',
          reason: 'the caller is the one holding a preference it expected to '
              'take effect, so the message states its side first');
    });

    test('a mixture of posture and explicit axis compares the effective value',
        () {
      // An axis given explicitly beats the posture's, which is the documented
      // contract. So these two agree on both key axes and differ only on what
      // the posture itself carries.
      final postured = preference(
          posture: PqPosture.pqActive,
          authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
          dataSigningKeyAlgorithms: const {});
      final plain =
          preference(authenticationKeyAlgorithm: SigningAlgoType.rsa2048);

      final differences = postured.rolloutDifferencesFrom(plain);
      expect(
          differences.any((d) => d.contains('authenticationKeyAlgorithm')),
          isFalse,
          reason: 'the effective algorithm is the same on both sides');
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
              asked: preference(
                  authenticationKeyAlgorithm: SigningAlgoType.mldsa65),
              cacheKey: '$atSign|enroll-a'),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', allOf(
                  contains('authenticationKeyAlgorithm'),
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
          AtClientImpl.create(
              atSign,
              'wavi',
              preference(
                  authenticationKeyAlgorithm: SigningAlgoType.mldsa65)),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', contains('authenticationKeyAlgorithm'))));

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
              atSign, 'wavi', preference(posture: strict)),
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
              preference(dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65})),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', contains('dataSigningKeyAlgorithms'))));

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
              asked: preference(posture: PqPosture.pqActive),
              cacheKey: atSign),
          returnsNormally);
    });
  });
}
