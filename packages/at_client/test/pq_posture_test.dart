import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// The rollout posture: every rollout axis as one value, three constants that
/// name the stages the release programme moves through, and the contract that
/// an explicitly set axis always beats the group it came from.
///
/// The three postures' values are pinned here as literals because they ARE the
/// release contract — apps plan deployments around what a stage means — and a
/// pin that read the values back through the type would follow an accidental
/// edit silently. An intended change edits the pin in the same commit, and
/// that edit is the review.
void main() {
  group('the posture values are the release contract', () {
    test('legacy drives no upgrade', () {
      const p = PqPosture.legacy;
      expect(p.authenticationKeyAlgorithm, SigningAlgoType.rsa2048);
      expect(p.dataSigningKeyAlgorithms, isEmpty,
          reason: 'no signing key of its own: the APKAM authentication key '
              'signs, and _apsk advertises that key as the bare public key '
              'string every deployed reader understands');
      expect(p.seedNamespaceKeys, false);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);
      expect(p.writesPqByDefault, false);
      expect(p.disallowLegacyEncryption, false);
      expect(p.mintLegacyMaterial, true);
    });

    test('pqReady moves the credentials and not the data path', () {
      const p = PqPosture.pqReady;
      expect(p.authenticationKeyAlgorithm, SigningAlgoType.mldsa65,
          reason: 'the quantum-forgeable credential moves FIRST: only the '
              'atServer verifies it, and that is the operator\'s own '
              'infrastructure, while every peer verifies the signing key');
      expect(p.dataSigningKeyAlgorithms, {SigningAlgoType.rsa2048},
          reason: 'one rsa2048 SIGNING key, which is exactly what the bare '
              '_apsk string can express — so an un-upgraded peer reads the '
              'advertisement unchanged while the AUTHENTICATION key moves to '
              'ML-DSA underneath');
      expect(p.seedNamespaceKeys, true);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(p.writesPqByDefault, false,
          reason: 'the whole point of this stage: keys move, data does not');
      expect(p.disallowLegacyEncryption, false);
      expect(p.mintLegacyMaterial, true);
    });

    test('pqActive is post-quantum by default', () {
      // Every axis as a raw literal, like the two above: this is the stage an
      // app adopts when it wants tomorrow's defaults today, and reading a
      // value back through the type would follow an accidental edit silently.
      const p = PqPosture.pqActive;
      expect(p.authenticationKeyAlgorithm, SigningAlgoType.mldsa65);
      expect(p.dataSigningKeyAlgorithms, {SigningAlgoType.mldsa65},
          reason: 'ML-DSA alone: a verifier takes the strongest algorithm the '
              'envelope and the advertisement share, so a second, weaker key '
              'would cost a signature per envelope to be passed over');
      expect(p.seedNamespaceKeys, true);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(p.writesPqByDefault, true);
      expect(p.disallowLegacyEncryption, true);
      expect(p.mintLegacyMaterial, true);
    });

    test('and it changes exactly two things against pqReady', () {
      // The claim ruling 113 makes about the last step of the ladder. Read
      // back against pqReady rather than re-listed, because "exactly two" is
      // a statement about the pair, not about either posture alone.
      const p = PqPosture.pqActive;
      const before = PqPosture.pqReady;

      expect(
          p.dataSigningKeyAlgorithms, isNot(before.dataSigningKeyAlgorithms));
      expect(p.writesPqByDefault, isNot(before.writesPqByDefault));

      expect(p.authenticationKeyAlgorithm, before.authenticationKeyAlgorithm);
      expect(p.seedNamespaceKeys, before.seedNamespaceKeys);
      expect(p.keyExchangeMode, before.keyExchangeMode);
      expect(p.mintLegacyMaterial, before.mintLegacyMaterial);
      // Refusing legacy writes is what "the PQ path is the default" means from
      // the other side, so it moves WITH writesPqByDefault rather than being a
      // third thing - and the class rejects the combination where it does not.
      expect(
          p.disallowLegacyEncryption, isNot(before.disallowLegacyEncryption));
    });

    test('legacy material is minted at every released stage', () {
      // Pinned as a group because the reason is a property of the set, not of
      // any one member: the ecosystem floor decides when an atSign can stop
      // holding legacy keys, and no client-side stage can know that.
      for (final p in [
        PqPosture.legacy,
        PqPosture.pqReady,
        PqPosture.pqActive
      ]) {
        expect(p.mintLegacyMaterial, true);
      }
    });
  });

  group('a program can build a posture of its own', () {
    test('every axis is required, and the combination is honoured', () {
      final custom = PqPosture(
        authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
        dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048},
        seedNamespaceKeys: true,
        keyExchangeMode: EnrollmentKeyExchangeMode.pq,
        writesPqByDefault: true,
        disallowLegacyEncryption: false,
        mintLegacyMaterial: false,
        sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
        keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024],
      );
      expect(custom.keyEstablishmentAlgorithms,
          const [SecretSharingAlgos.mlKem1024],
          reason: 'the receiver-side list is an axis like any other, and a '
              'bespoke posture states it rather than inheriting a default');
      expect(custom.mintLegacyMaterial, false,
          reason: 'the axis exists so the stop-release can flip it');
      expect(custom.writesPqByDefault, true);
      expect(custom.disallowLegacyEncryption, false);
    });

    test('a posture that would refuse its own writes is rejected', () {
      // Rejected at construction rather than accepted and left to fail at the
      // first put, where the app would read it as a data-path bug.
      expect(
          () => PqPosture(
                authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
                dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65},
                seedNamespaceKeys: true,
                keyExchangeMode: EnrollmentKeyExchangeMode.pq,
                writesPqByDefault: false,
                disallowLegacyEncryption: true,
                mintLegacyMaterial: true,
                sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
                keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
              ),
          throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
              'message', contains('refuses its own writes'))));
    });

    test('the coupling is one-way — writing PQ without refusing legacy is fine',
        () {
      // The inverse is a real deployment: write post-quantum where you can and
      // fall back where you must, which is what the era default does today.
      expect(
          PqPosture(
            authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
            dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65},
            seedNamespaceKeys: true,
            keyExchangeMode: EnrollmentKeyExchangeMode.pq,
            writesPqByDefault: true,
            disallowLegacyEncryption: false,
            mintLegacyMaterial: true,
            sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
            keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
          ).writesPqByDefault,
          true);
    });
  });

  group('the preference applies the posture at construction', () {
    test('a bare preference runs the pqReady posture', () {
      // The shipped default, pinned as a raw expectation rather than derived
      // from the constant, so moving the default is an edit here and that
      // edit is the review. It moved legacy → pqReady for this release
      // candidate; 4.0 moves it again, to pqActive.
      final preference = AtClientPreference();
      expect(preference.posture, same(PqPosture.pqReady),
          reason: 'the default stage is the default — an app that names '
              'nothing rides the SDK\'s own rollout schedule');
      // Still false at pqReady, and it is pqActive that turns it on: this
      // stage reads post-quantum and goes on writing what the fleet can read.
      expect(preference.disallowLegacyEncryption, false);
      expect(preference.authenticationKeyAlgorithm, SigningAlgoType.mldsa65);
      expect(preference.dataSigningKeyAlgorithms, {SigningAlgoType.rsa2048});
      expect(preference.seedNamespaceKeys, true);
    });

    test('pqActive sets disallowLegacyEncryption', () {
      final preference = AtClientPreference(posture: PqPosture.pqActive);
      expect(preference.disallowLegacyEncryption, true);
    });

    test('disallowLegacyEncryption has no per-preference override', () {
      // The deliberate asymmetry of ruling 113: the algorithm lists keep an
      // escape hatch and this does not, because a safety flag whose override
      // defeats its purpose is not the same kind of thing as deployment
      // policy. There is no constructor argument to test, so what is asserted
      // is that the posture is the only thing that moves it.
      expect(AtClientPreference().disallowLegacyEncryption, false);
      expect(
          AtClientPreference(posture: PqPosture.pqReady)
              .disallowLegacyEncryption,
          false);
      expect(
          AtClientPreference(posture: PqPosture.pqActive)
              .disallowLegacyEncryption,
          true);
      // Naming the other axes explicitly does not move it either, which is
      // what makes this posture-only rather than merely posture-defaulted.
      expect(
          AtClientPreference(
              posture: PqPosture.pqActive,
              authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
              dataSigningKeyAlgorithms: const {}).disallowLegacyEncryption,
          true);
    });

    test('seeding follows the posture and stays assignable afterwards', () {
      expect(AtClientPreference(posture: PqPosture.pqReady).seedNamespaceKeys,
          true,
          reason: 'clients mint and publish while still writing legacy, so '
              'that by the time PQ writes switch on the keys are already '
              'everywhere');
      expect(AtClientPreference(posture: PqPosture.pqActive).seedNamespaceKeys,
          true);
      // Mutable, unlike the axes fixed at construction: seeding changes what
      // this client publishes about itself, not what it writes for others.
      expect(
          AtClientPreference(posture: PqPosture.pqReady)
            ..seedNamespaceKeys = false,
          isA<AtClientPreference>()
              .having((p) => p.seedNamespaceKeys, 'seedNamespaceKeys', false));
    });
  });

  group('the authentication key algorithm', () {
    test('follows the posture, and an explicit value beats it', () {
      expect(
          AtClientPreference(posture: PqPosture.pqReady)
              .authenticationKeyAlgorithm,
          SigningAlgoType.mldsa65);
      expect(
          AtClientPreference(
                  posture: PqPosture.pqReady,
                  authenticationKeyAlgorithm: SigningAlgoType.rsa2048)
              .authenticationKeyAlgorithm,
          SigningAlgoType.rsa2048,
          reason: 'a deployment whose atServer cannot verify ML-DSA PKAM yet '
              'says so here, without giving up the rest of the stage');
      expect(
          AtClientPreference(
                  authenticationKeyAlgorithm: SigningAlgoType.mldsa65)
              .authenticationKeyAlgorithm,
          SigningAlgoType.mldsa65);
    });

    test('it is a separate axis from the data signing keys', () {
      // The two moved together while they were one enum, and pqReady is the
      // stage that exists precisely because they must not.
      const p = PqPosture.pqReady;
      expect(p.authenticationKeyAlgorithm, SigningAlgoType.mldsa65);
      expect(
          p.dataSigningKeyAlgorithms, isNot(contains(SigningAlgoType.mldsa65)));
    });
  });

  group('the data signing set', () {
    test('follows the posture, and an explicit set beats it both ways', () {
      expect(AtClientPreference().dataSigningKeyAlgorithms,
          {SigningAlgoType.rsa2048},
          reason: 'the shipped default is pqReady, which keeps one active '
              'signing key and keeps it classical — the array form a deployed '
              'reader cannot parse is what 4.0 takes on');
      expect(
          AtClientPreference(posture: PqPosture.pqActive)
              .dataSigningKeyAlgorithms,
          {SigningAlgoType.mldsa65});
      expect(
          AtClientPreference(
              posture: PqPosture.pqActive,
              dataSigningKeyAlgorithms: const {}).dataSigningKeyAlgorithms,
          isEmpty);
      expect(
          AtClientPreference(
                  dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})
              .dataSigningKeyAlgorithms,
          {SigningAlgoType.rsa2048});
    });

    test('refuses an algorithm this build cannot sign an envelope under', () {
      // The refusal is at construction rather than at signing time: an app
      // that asked for a post-quantum signature and was quietly given a
      // classical one has no way to notice.
      expect(
          () => AtClientPreference(
              dataSigningKeyAlgorithms: const {SigningAlgoType.ecc_secp256r1}),
          throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
              'message', contains('mldsa65, rsa2048'))));
      expect(
          () => AtClientPreference(
              dataSigningKeyAlgorithms: const {SigningAlgoType.ed25519}),
          throwsArgumentError);
      expect(
          () => AtClientPreference(
              dataSigningKeyAlgorithms: const {SigningAlgoType.rsa4096}),
          throwsArgumentError);
      // The two this build does sign under, named as literals: a set derived
      // from what canSignEnvelopeWith answers would follow the signer's
      // capability silently, and what an app may ask for is a claim about
      // this release.
      for (final signable in [
        SigningAlgoType.mldsa65,
        SigningAlgoType.rsa2048
      ]) {
        expect(
            AtClientPreference(dataSigningKeyAlgorithms: {signable})
                .dataSigningKeyAlgorithms,
            {signable});
      }
    });

    test('the set a caller keeps cannot be added to afterwards', () {
      // Final at construction is worth nothing if the contents are not: the
      // check runs once, and a set the caller still holds a reference to
      // would otherwise be a way past it.
      final requested = <SigningAlgoType>{SigningAlgoType.rsa2048};
      final preference =
          AtClientPreference(dataSigningKeyAlgorithms: requested);
      requested.add(SigningAlgoType.ecc_secp256r1);
      expect(preference.dataSigningKeyAlgorithms, {SigningAlgoType.rsa2048});
      expect(
          () =>
              preference.dataSigningKeyAlgorithms.add(SigningAlgoType.mldsa65),
          throwsUnsupportedError);
    });
  });

  group('the seal-to list', () {
    test('every released stage names the same list, as a raw literal', () {
      // Raw ids rather than SecretSharingAlgos.keyAlgos: reading the value
      // back through the constant it is defaulted from would follow an edit to
      // that constant silently, and what a released stage seals to is a claim
      // about this release. Order is meaning - it decides which of a
      // recipient's advertised keys is picked.
      for (final p in [
        PqPosture.legacy,
        PqPosture.pqReady,
        PqPosture.pqActive
      ]) {
        expect(p.sealsToKeyAlgorithms, ['x-wing', 'ml-kem-1024']);
      }
    });

    /// The OTHER key-establishment axis, and until 2026-08-26 no test pinned
    /// it for any posture.
    ///
    /// ⚠️ **Proven by mutation, not suspected:** changing
    /// `PqPosture.pqActive.keyEstablishmentAlgorithms` from `[x-wing]` to
    /// `[ml-kem-1024]` left the whole at_client suite — 1573 tests — green.
    /// Found by the citation audit while checking UC-C1.6's "all seven axes".
    ///
    /// It is not interchangeable with [sealsToKeyAlgorithms] above and the
    /// two are easy to conflate: that one is what this client will seal *to*,
    /// a sender-side preference among what a recipient offers. This one is
    /// what this atSign **advertises for others to seal to it**, so it decides
    /// the algorithm of the encapsulation key minted at the next mint — and an
    /// accidental edit changes what every peer encrypts to this atSign with.
    ///
    /// Raw ids for the same reason the list above uses them: reading the value
    /// back through `SecretSharingAlgos.xWing` would follow an edit to that
    /// constant silently.
    test('every released stage advertises the same key-establishment list', () {
      for (final p in [
        PqPosture.legacy,
        PqPosture.pqReady,
        PqPosture.pqActive
      ]) {
        expect(p.keyEstablishmentAlgorithms, ['x-wing'],
            reason: 'the hybrid alone is what a released stage advertises. '
                'Widening it is a deployment decision an operator makes '
                'through AtClientPreference, never something a posture does '
                'on its behalf');
      }
    });

    test('the stages agree because it is a deployment choice, not a stage', () {
      // Ruling 50.3, restated as an assertion: which KEM an atSign will use is
      // where it is deployed, not how far through the rollout it is. If a
      // future stage ever differs here, that ruling moved and this row is the
      // place it has to be argued.
      expect(PqPosture.pqActive.sealsToKeyAlgorithms,
          PqPosture.legacy.sealsToKeyAlgorithms);
    });

    test('narrowing it is honoured, and is the only way to refuse a peer', () {
      final fipsOnly = AtClientPreference(
          sealsToKeyAlgorithms: const [SecretSharingAlgos.mlKem1024]);

      expect(fipsOnly.sealsToKeyAlgorithms, [SecretSharingAlgos.mlKem1024]);
      // The default refuses nobody, which is what makes narrowing a decision
      // rather than an accident.
      expect(
          AtClientPreference().sealsToKeyAlgorithms,
          containsAll(
              [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]));
    });

    test('reordering it is a different client, not an equal one', () {
      // Unlike the signing set, where membership is the whole meaning. Here
      // the order decides which of two advertised keys a sender picks, so two
      // lists holding the same ids in a different order behave differently.
      final strongestFirst = AtClientPreference();
      final reversed = AtClientPreference(
          sealsToKeyAlgorithms:
              strongestFirst.sealsToKeyAlgorithms.reversed.toList());

      expect(strongestFirst.rolloutDifferencesFrom(reversed),
          [contains('sealsToKeyAlgorithms')]);
    });

    test('an algorithm this build cannot seal under is refused', () {
      // At construction, where the deployment wrote it - not at the first
      // write to a peer, by which time the misspelling looks like the peer's
      // advertisement being wrong.
      expect(
          () => AtClientPreference(sealsToKeyAlgorithms: const ['ml-kem-768']),
          throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
              'message', contains('x-wing, ml-kem-1024'))));
    });

    test('the list a caller keeps cannot be added to afterwards', () {
      final requested = <String>[SecretSharingAlgos.mlKem1024];
      final preference = AtClientPreference(sealsToKeyAlgorithms: requested);
      requested.add(SecretSharingAlgos.xWing);

      expect(preference.sealsToKeyAlgorithms, [SecretSharingAlgos.mlKem1024],
          reason: 'the check runs once, so a list the caller still holds a '
              'reference to would be a way past it');
      expect(
          () => preference.sealsToKeyAlgorithms.add(SecretSharingAlgos.xWing),
          throwsUnsupportedError);
    });
  });

  // The envelope shape was an axis here until it stopped being a choice:
  // there is one shape, so a posture has nothing to say about it.
}
