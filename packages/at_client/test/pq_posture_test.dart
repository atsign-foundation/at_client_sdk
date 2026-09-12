import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// The rollout posture: every rollout axis as one value, the constants naming
/// the stages of the ladder, and the contract that an explicitly set axis beats
/// the group it came from.
///
/// The postures' values are pinned as raw literals because they ARE the release
/// contract; a pin that read them back through the type would follow an
/// accidental edit silently.
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
      expect(p.configuresPqProviders, false,
          reason: 'the axis that makes this a stand-in for a build predating '
              'the post-quantum providers rather than a current build '
              'configured conservatively: an inbound record stamped with one '
              'of them is refused, as a released pre-capability build '
              'refuses it');
      expect(p.disallowLegacyEncryption, false);
      expect(p.mintLegacyMaterial, true);
    });

    test('legacy is the only stage that configures no post-quantum providers',
        () {
      final withoutProviders = [
        PqPosture.legacy,
        PqPosture.pqReady,
        PqPosture.pqActive
      ].where((p) => !p.configuresPqProviders).toList();

      expect(withoutProviders, hasLength(1),
          reason: 'more than one such stage, or none, means the ladder no '
              'longer has exactly one pre-capability position');
      expect(identical(withoutProviders.single, PqPosture.legacy), isTrue,
          reason: 'and it must be the earliest stage — a later one declining '
              'the providers would be a downgrade rather than a starting '
              'point');
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
      expect(p.configuresPqProviders, true);
      expect(p.disallowLegacyEncryption, false);
      expect(p.mintLegacyMaterial, true);
    });

    test('pqActive is post-quantum by default', () {
      // NOTE: not every axis is pinned here. The two holding the same value at
      // every released stage — `sealsToKeyAlgorithms` and
      // `keyEstablishmentAlgorithms` — are pinned once each in the 'seal-to
      // list' group below, across every stage, rather than once per stage here.
      const p = PqPosture.pqActive;
      expect(p.authenticationKeyAlgorithm, SigningAlgoType.mldsa65);
      expect(p.dataSigningKeyAlgorithms, {SigningAlgoType.mldsa65},
          reason: 'ML-DSA alone: a verifier takes the strongest algorithm the '
              'envelope and the advertisement share, so a second, weaker key '
              'would cost a signature per envelope to be passed over');
      expect(p.seedNamespaceKeys, true);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(p.writesPqByDefault, true);
      expect(p.configuresPqProviders, true);
      expect(p.disallowLegacyEncryption, true);
      expect(p.mintLegacyMaterial, true);
    });

    test('and it changes exactly two things against pqReady', () {
      // "Exactly two" is a statement about the pair, so the axes are read back
      // against pqReady rather than re-listed.
      const p = PqPosture.pqActive;
      const before = PqPosture.pqReady;

      expect(
          p.dataSigningKeyAlgorithms, isNot(before.dataSigningKeyAlgorithms));
      expect(p.writesPqByDefault, isNot(before.writesPqByDefault));

      expect(p.authenticationKeyAlgorithm, before.authenticationKeyAlgorithm);
      expect(p.seedNamespaceKeys, before.seedNamespaceKeys);
      expect(p.keyExchangeMode, before.keyExchangeMode);
      expect(p.configuresPqProviders, before.configuresPqProviders);
      expect(p.mintLegacyMaterial, before.mintLegacyMaterial);
      // NOTE: refusing legacy writes is what "the PQ path is the default"
      // means from the other side, so it moves WITH writesPqByDefault rather
      // than counting as a third change - and the class rejects the
      // combination where it does not.
      expect(
          p.disallowLegacyEncryption, isNot(before.disallowLegacyEncryption));
    });

    test('legacy material is minted at every released stage', () {
      // Pinned as a group because the reason is a property of the set, not of
      // any one member: the ecosystem floor decides when an atSign can stop
      // holding legacy keys, and no client-side stage knows that.
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
        configuresPqProviders: true,
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
                configuresPqProviders: true,
                disallowLegacyEncryption: true,
                mintLegacyMaterial: true,
                sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
                keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
              ),
          throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
              'message', contains('refuses its own writes'))));
    });

    test(
        'the coupling is one-way — writing PQ without refusing the legacy provider is fine',
        () {
      // The inverse is a real deployment: write post-quantum where you can and
      // fall back where you must.
      expect(
          PqPosture(
            authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
            dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65},
            seedNamespaceKeys: true,
            keyExchangeMode: EnrollmentKeyExchangeMode.pq,
            writesPqByDefault: true,
            configuresPqProviders: true,
            disallowLegacyEncryption: false,
            mintLegacyMaterial: true,
            sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
            keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
          ).writesPqByDefault,
          true);
    });
  });

  group('the preference applies the posture at construction', () {
    test('a bare preference runs the legacy posture', () {
      // The shipped default, pinned as a raw expectation rather than derived
      // from the constant, so moving the default is an edit here. What an app
      // gets when it names nothing is the CONTROL arm: no post-quantum
      // machinery in the picture, so anything it breaks can be reproduced
      // without it. A developer who wants a later stage names one.
      final preference = AtClientPreference();
      expect(preference.posture, same(PqPosture.legacy),
          reason: 'the default stage is the default — an app that names '
              'nothing gets the stage the rollout is debugged against');
      expect(preference.disallowLegacyEncryption, false);
      expect(preference.authenticationKeyAlgorithm, SigningAlgoType.rsa2048,
          reason: 'classical throughout: this drives no upgrade');
      expect(preference.dataSigningKeyAlgorithms, isEmpty,
          reason: 'the enrollment holds no signing key of its own, so its '
              'APKAM authentication key signs and `_apsk` advertises it bare');
      expect(preference.seedNamespaceKeys, false);
      expect(preference.posture.configuresPqProviders, false,
          reason: 'the axis that makes this a control rather than a '
              'conservatively configured current build');
    });

    test('pqActive sets disallowLegacyEncryption', () {
      final preference = AtClientPreference(posture: PqPosture.pqActive);
      expect(preference.disallowLegacyEncryption, true);
    });

    test('disallowLegacyEncryption has no per-preference override', () {
      // A deliberate asymmetry: the algorithm lists keep an escape hatch and
      // this does not, because a safety flag whose override defeats its purpose
      // is not the same kind of thing as deployment policy. There is no
      // constructor argument to test, so what is asserted is that the posture
      // is the only thing that moves it.
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
      // what makes this posture-only rather than merely posture-defaulted. The
      // mixture is legal: a signing set WEAKER than the posture is deliberately
      // still allowed — pqActive with {rsa2048} mints rsa2048 and keeps `_apsk`
      // bare, which is coherent.
      expect(
          AtClientPreference(
                  posture: PqPosture.pqActive,
                  authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
                  dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})
              .disallowLegacyEncryption,
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

  group('a posture that configures no post-quantum providers', () {
    AtClientPreference at(PqPosture posture) =>
        AtClientPreference(posture: posture)
          ..hiveStoragePath = 'test/hive'
          ..commitLogPath = 'test/hive/path';

    test('refuses a crypto config that registers them', () {
      // NOTE: the only row that fails if the refusal is deleted — every other
      // `.crypto =` site either sits on a configuring posture or registers a
      // non-post-quantum id.
      expect(
          () => at(PqPosture.legacy).crypto =
              CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()),
          throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message',
              contains('configures no post-quantum providers'))),
          reason: 'a client standing in for a build that predates these '
              'schemes must not be handed them');
    });

    test('the refusal names the ids it declined', () {
      // An operator has to be able to see WHICH provider was the problem;
      // a refusal naming none of them cannot be acted on.
      try {
        at(PqPosture.legacy).crypto =
            CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());
        fail('the assignment should have been refused');
      } on ArgumentError catch (e) {
        expect('${e.invalidValue}', contains(symmetricAesGcmCryptoProviderId));
        expect('${e.invalidValue}', contains(nskeyCryptoProviderId));
      }
    });

    test('a configuring posture takes the same config', () {
      // Control 1: the refusal keys on the posture, not on the config. Without
      // this the row above passes for a guard that refuses every caller.
      expect(
          () => at(PqPosture.pqReady).crypto =
              CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()),
          returnsNormally);
    });

    test('the same posture takes a config with no post-quantum providers', () {
      // Control 2: it keys on the config, not on the posture. The two controls
      // together are what make the refusal a discriminator rather than a
      // blanket.
      expect(() => at(PqPosture.legacy).crypto = const CryptoConfig.legacy(),
          returnsNormally);
    });

    test('the declined set covers every provider the SDK builds', () {
      // The enumeration duty the set states in its dartdoc, checked: a fourth
      // post-quantum scheme added without touching the set would pass the
      // refusal silently, handing a pre-capability client exactly the provider
      // it is meant not to have.
      final built = CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing())
          .providers
          .map((p) => p.id)
          .toSet();
      expect(built, isNotEmpty,
          reason: 'if the set assembled nothing, the row below compares two '
              'empty sets and passes having measured nothing');
      expect(pqCryptoProviderIds, containsAll(built),
          reason: 'every provider CryptoConfig.nskey registers must be one the '
              'refusal knows to decline; add the new id to pqCryptoProviderIds '
              'in the same commit as the provider');
    });

    test("an app's own provider is not declined", () {
      // The extension seam: only the ids this SDK ships for the post-quantum
      // path are refused, so an app registering a provider of its own on the
      // earliest stage is unaffected.
      expect(
          () => at(PqPosture.legacy).crypto =
              const CryptoConfig(defaultProviderId: legacyCryptoProviderId),
          returnsNormally);
    });
  });

  group('the authentication key algorithm', () {
    test('follows the posture, and an explicit value beats it', () {
      expect(
          AtClientPreference(posture: PqPosture.pqReady)
              .authenticationKeyAlgorithm,
          SigningAlgoType.mldsa65);
      // Named against `pqReady`, not against a bare preference: the default is
      // `legacy`, whose data signing set is EMPTY, and the coherence rule
      // refuses an empty set beside a post-quantum authentication key. With no
      // signing key of its own the enrollment signs with its authentication
      // key, and `_apsk` must be able to state that key in the bare form every
      // deployed reader parses, which only rsa2048 can.
      expect(
          AtClientPreference(
                  posture: PqPosture.pqReady,
                  authenticationKeyAlgorithm: SigningAlgoType.mldsa65)
              .authenticationKeyAlgorithm,
          SigningAlgoType.mldsa65,
          reason: 'raising an axis above the posture is what "beats it" means '
              'now, and naming it explicitly is still allowed');
    });

    test('but an explicit value may not be WEAKER than the posture', () {
      // A posture is a floor: an app that must not move names
      // PqPosture.legacy, rather than keeping a stronger posture and weakening
      // an axis it is made of.
      expect(
          () => AtClientPreference(
              posture: PqPosture.pqReady,
              authenticationKeyAlgorithm: SigningAlgoType.rsa2048),
          throwsA(isA<ArgumentError>()));
    });

    test('it is a separate axis from the data signing keys', () {
      // pqReady is the stage that exists precisely because the two must be
      // able to move apart.
      const p = PqPosture.pqReady;
      expect(p.authenticationKeyAlgorithm, SigningAlgoType.mldsa65);
      expect(
          p.dataSigningKeyAlgorithms, isNot(contains(SigningAlgoType.mldsa65)));
    });
  });

  group('the data signing set', () {
    test('follows the posture, and an explicit set beats it both ways', () {
      expect(AtClientPreference().dataSigningKeyAlgorithms, isEmpty,
          reason:
              'the shipped default is the legacy posture, where the enrollment holds '
              'no signing key of its own and its APKAM authentication key '
              'signs — which is what `_apsk` advertises, bare');
      expect(
          AtClientPreference(posture: PqPosture.pqReady)
              .dataSigningKeyAlgorithms,
          {SigningAlgoType.rsa2048},
          reason: 'pqReady is where the enrollment gains a signing key of its '
              'own, and keeps it classical — the array form a deployed reader '
              'cannot parse is what the stage after takes on');
      expect(
          AtClientPreference(posture: PqPosture.pqActive)
              .dataSigningKeyAlgorithms,
          {SigningAlgoType.mldsa65});
      expect(
          () => AtClientPreference(
              posture: PqPosture.pqActive, dataSigningKeyAlgorithms: const {}),
          throwsA(isA<ArgumentError>()),
          reason: '⛔ this pinned an empty set beside pqActive as supported '
              'until 2026-08-30. An enrollment holding no data signing key '
              'signs with its authentication key and advertises it, and '
              'pqActive authenticates with ML-DSA — which the bare `_apsk` '
              'form cannot state, so the record becomes the array a deployed '
              'reader cannot parse. Emptying the set needs rsa2048 beside it');
      expect(
          AtClientPreference(
              posture: PqPosture.legacy,
              dataSigningKeyAlgorithms: const {}).dataSigningKeyAlgorithms,
          isEmpty,
          reason: 'and the control: an empty set is still exactly what legacy '
              'means, because legacy authenticates with rsa2048');
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
      // capability silently.
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
      // The check runs once, so a set the caller still holds a reference to
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
      // that constant silently. Order is meaning - it decides which of a
      // recipient's advertised keys is picked.
      for (final p in [
        PqPosture.legacy,
        PqPosture.pqReady,
        PqPosture.pqActive
      ]) {
        expect(p.sealsToKeyAlgorithms, ['x-wing', 'ml-kem-1024']);
      }
    });

    // NOTE: the other key-establishment axis, easily conflated with
    // sealsToKeyAlgorithms above. That one is what this client will seal *to*,
    // a sender-side preference among what a recipient offers; this one is what
    // this atSign advertises for others to seal to it, so it decides the
    // algorithm of the encapsulation key minted at the next mint — an
    // accidental edit changes what every peer encrypts to this atSign with.
    // Raw ids for the same reason the list above uses them.
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
      // Which KEM an atSign will use is a property of where it is deployed,
      // not of how far through the rollout it is.
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
      // Unlike the signing set, where membership is the whole meaning: here
      // the order decides which of two advertised keys a sender picks.
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

  // There is one envelope shape, so a posture has nothing to say about it.
}
