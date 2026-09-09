import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// A client that already exists keeps the rollout axes it was built under, and
/// a caller handing over different ones is refused rather than ignored.
///
/// Two paths hand back a client that already exists, and only one is the cache:
/// `AtClientManager.setCurrentAtSign` short-circuits on a same-atSign call
/// carrying no override argument and returns without calling
/// `AtClientImpl.create` at all, so a guard on the cache alone would miss the
/// ordinary path.
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

  /// The same, but holding a data signing key.
  ///
  /// The constructor refuses an empty signing set beside anything but rsa2048
  /// authentication, so a row varying the authentication axis alone needs one.
  AtClientPreference signing({SigningAlgoType? authenticationKeyAlgorithm}) =>
      preference(
          authenticationKeyAlgorithm: authenticationKeyAlgorithm,
          dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048});

  /// The smallest posture that refuses legacy writes.
  ///
  /// `PqPosture` rejects refusing legacy writes while still writing legacy by
  /// default, so `writesPqByDefault` moves with it and the two are never
  /// reported apart.
  final strict = PqPosture(
    authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
    dataSigningKeyAlgorithms: const {},
    seedNamespaceKeys: false,
    keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
    writesPqByDefault: true,
    configuresPqProviders: true,
    disallowLegacyEncryption: true,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
  );

  group('what counts as the same settings', () {
    test('two separately built default preferences are interchangeable', () {
      // NOTE: callers hand over a fresh preference object on every call, so an
      // identity comparison here would refuse every one of them.
      expect(preference().rolloutDifferencesFrom(preference()), isEmpty);
    });

    test('a hand-built posture equal to a constant is the same posture', () {
      // NOTE: PqPosture declares no ==, so comparing postures as objects
      // compares identity and a hand-built one reads as a mismatch.
      final canonical = preference(posture: PqPosture.legacy);
      final built = preference(
          posture: PqPosture(
        authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
        dataSigningKeyAlgorithms: const {},
        seedNamespaceKeys: false,
        keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
        writesPqByDefault: false,
        configuresPqProviders: false,
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
          signing().rolloutDifferencesFrom(
              signing(authenticationKeyAlgorithm: SigningAlgoType.mldsa65)),
          [contains('authenticationKeyAlgorithm')]);
    });

    test('the refusal never moves alone, and both halves are reported', () {
      expect(
          preference().rolloutDifferencesFrom(preference(posture: strict)),
          containsAll([
            contains('posture.writesPqByDefault'),
            contains('disallowLegacyEncryption'),
          ]));
    });

    test('the two key axes move independently, and are reported that way', () {
      expect(
          signing().rolloutDifferencesFrom(
              signing(authenticationKeyAlgorithm: SigningAlgoType.mldsa65)),
          ['authenticationKeyAlgorithm (asked mldsa65, running rsa2048)']);
      expect(
          preference().rolloutDifferencesFrom(preference(
              dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})),
          ['dataSigningKeyAlgorithms (asked {rsa2048}, running {})']);
    });

    test('a posture difference is named by what it means', () {
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
          reason: 'one posture moves six compared axes, and a diagnostic '
              'naming only the first would send a reader looking for one '
              'setting');
    });

    test('the difference reads as asked-versus-running', () {
      final running = signing();
      final asked =
          signing(authenticationKeyAlgorithm: SigningAlgoType.mldsa65);

      expect(running.rolloutDifferencesFrom(asked).single,
          'authenticationKeyAlgorithm (asked mldsa65, running rsa2048)',
          reason: 'the caller is the one holding a preference it expected to '
              'take effect, so the message states its side first');
    });

    test('a mixture of posture and explicit axis compares the effective value',
        () {
      // NOTE: an axis given explicitly beats the posture's, so these two agree
      // on both key axes and differ only in what the posture itself carries.
      final postured = preference(posture: PqPosture.pqActive);
      final plain = preference(
          authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
          dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65});

      final differences = postured.rolloutDifferencesFrom(plain);
      expect(differences.any((d) => d.contains('authenticationKeyAlgorithm')),
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
    // NOTE: stop() each client — clearing the map alone leaves it holding its
    // storage location, which the next build is refused at.
    Future<void> dropClients() async {
      for (final client
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await (client as AtClientImpl).stop();
      }
      AtClientImpl.atClientInstanceMap.clear();
    }

    setUp(dropClients);
    tearDown(dropClients);

    test('names the axis, the client and what to do about it', () {
      expect(
          () => AtClientImpl.refuseChangedRolloutAxes(
              running: signing(),
              asked:
                  signing(authenticationKeyAlgorithm: SigningAlgoType.mldsa65),
              cacheKey: '$atSign|enroll-a'),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e',
              'message',
              allOf(
                  contains('authenticationKeyAlgorithm'),
                  contains('$atSign|enroll-a'),
                  contains('final at construction')))));
    });

    test('says nothing when the settings agree', () {
      expect(
          () => AtClientImpl.refuseChangedRolloutAxes(
              running: preference(), asked: preference(), cacheKey: atSign),
          returnsNormally);
    });

    test('and the cache actually asks it', () async {
      final first = await AtClientImpl.create(atSign, 'wavi', signing());

      await expectLater(
          AtClientImpl.create(atSign, 'wavi',
              signing(authenticationKeyAlgorithm: SigningAlgoType.mldsa65)),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', contains('authenticationKeyAlgorithm'))));

      // The control: without it the row above passes for a build that refuses
      // every second create.
      expect(
          identical(
              await AtClientImpl.create(atSign, 'wavi', signing()), first),
          isTrue);
    });

    test('and the manager\'s same-atSign short-circuit asks it too', () async {
      // NOTE: with no override argument setCurrentAtSign returns the client it
      // already has without calling create, so a throw here is proof that the
      // second guard fired — nothing else on this path can raise one.
      final manager = AtClientManager(atSign);
      await manager.setCurrentAtSign(atSign, 'wavi', preference());

      await expectLater(
          manager.setCurrentAtSign(atSign, 'wavi', preference(posture: strict)),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', contains('disallowLegacyEncryption'))));

      await manager.setCurrentAtSign(atSign, 'wavi', preference());
    });

    test('and so does setPreferences, which names its replacement', () async {
      // NOTE: the substrate read these axes at a startup that has already run,
      // so accepting a replacement would leave the client reporting a stage it
      // never applied.
      final client = await AtClientImpl.create(atSign, 'wavi', preference());

      expect(
          () => client.setPreferences(preference(
              dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65})),
          throwsA(isA<ArgumentError>().having(
              (e) => '$e', 'message', contains('dataSigningKeyAlgorithms'))));

      // The control: everything outside the rollout axes is still replaced.
      client.setPreferences(preference()..syncBatchSize = 42);
      expect(client.getPreferences()!.syncBatchSize, 42);
    });

    test('a client with no preference at all is not refused', () {
      // NOTE: refusing here would report a client that has not finished being
      // built as a stage mismatch.
      expect(
          () => AtClientImpl.refuseChangedRolloutAxes(
              running: null,
              asked: preference(posture: PqPosture.pqActive),
              cacheKey: atSign),
          returnsNormally);
    });
  });
}
