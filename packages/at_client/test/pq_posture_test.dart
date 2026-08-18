import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// The rollout posture: the five flags of `docs/projects/pq/decisions.md`
/// 56.4 as one value, and the contract that an explicitly set flag always
/// beats it.
///
/// The two postures' values are pinned here as literals because they ARE the
/// release contract — "3.x defaults" and "4.0 defaults" are claims apps plan
/// deployments around, and a pin that read the values back through the type
/// would follow an accidental edit silently.
void main() {
  group('the posture values are the release contract', () {
    test('migration is the 3.x column of the rollout table', () {
      const p = PqPosture.migration();
      expect(p.writesPqByDefault, false);
      expect(p.disallowLegacyEncryption, false);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);
      expect(p.retrofitAuthenticationAlgo, SigningAlgoType.rsa2048);
      expect(p.signingRollout, SigningRollout.now);
      expect(p.inUseSigningAlgorithms, isEmpty,
          reason: 'no signing key of its own: the APKAM authentication key '
              'signs, and _apsk advertises that key as the bare public key '
              'string every deployed reader understands');
    });

    test('postQuantum is the 4.0 column of the rollout table', () {
      const p = PqPosture.postQuantum();
      expect(p.writesPqByDefault, true);
      expect(p.disallowLegacyEncryption, true);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(p.retrofitAuthenticationAlgo, SigningAlgoType.mldsa65);
      expect(p.signingRollout, SigningRollout.rollout2);
      expect(p.inUseSigningAlgorithms, {SigningAlgoType.mldsa65},
          reason: 'ML-DSA alone: a verifier takes the strongest algorithm the '
              'envelope and the advertisement share, so a second, weaker key '
              'would cost a signature per envelope to be passed over');
    });
  });

  group('the preference applies the posture at construction', () {
    test('a bare preference runs the migration posture', () {
      final preference = AtClientPreference();
      expect(preference.posture, same(const PqPosture.migration()),
          reason: 'the 3.x defaults are the defaults — an app that names '
              'nothing rides the SDK\'s own migration schedule');
      expect(preference.disallowLegacyEncryption, false);
    });

    test('postQuantum sets disallowLegacyEncryption', () {
      final preference =
          AtClientPreference(posture: const PqPosture.postQuantum());
      expect(preference.disallowLegacyEncryption, true);
    });

    test('an explicit disallowLegacyEncryption beats the posture, both ways',
        () {
      expect(
          AtClientPreference(
                  posture: const PqPosture.postQuantum(),
                  disallowLegacyEncryption: false)
              .disallowLegacyEncryption,
          false,
          reason: 'the posture supplies defaults; a flag the app set itself '
              'is the app\'s decision for that one axis');
      expect(
          AtClientPreference(disallowLegacyEncryption: true)
              .disallowLegacyEncryption,
          true);
    });
  });

  group('the signing rollout stage', () {
    test('each stage names the set a client at that stage signs with', () {
      // Raw literals: these three are the rollout's contract, and a pin that
      // read them back through the enum would follow an accidental edit.
      expect(SigningRollout.now.defaultInUseSigningAlgorithms, isEmpty);
      expect(SigningRollout.rollout1.defaultInUseSigningAlgorithms,
          {SigningAlgoType.rsa2048},
          reason: 'rollout 1 holds one rsa2048 SIGNING key, which is exactly '
              'what the bare _apsk string can express — so an un-upgraded '
              'peer reads it unchanged while the AUTHENTICATION key moves to '
              'ML-DSA underneath');
      expect(SigningRollout.rollout2.defaultInUseSigningAlgorithms,
          {SigningAlgoType.mldsa65});
    });

    test('each stage names the authentication algorithm a retrofit mints', () {
      // The other half of the same position. Raw literals for the same
      // reason, and the member name says AUTHENTICATION where the wire field
      // it feeds (EnrollParams.signingAlgo) cannot be renamed.
      expect(SigningRollout.now.defaultRetrofitAuthenticationAlgo,
          SigningAlgoType.rsa2048);
      expect(SigningRollout.rollout1.defaultRetrofitAuthenticationAlgo,
          SigningAlgoType.mldsa65,
          reason: 'the quantum-forgeable credential moves FIRST: only the '
              'atServer verifies it, and that is the operator\'s own '
              'infrastructure, while every peer verifies the signing key');
      expect(SigningRollout.rollout2.defaultRetrofitAuthenticationAlgo,
          SigningAlgoType.mldsa65);
    });

    test('the posture derives its set from the stage, never storing both', () {
      // Two stored fields would be two controls over one behaviour, and the
      // day they disagreed one would be a lie with no way to tell which.
      for (final posture in [
        const PqPosture.migration(),
        const PqPosture.postQuantum()
      ]) {
        expect(posture.inUseSigningAlgorithms,
            posture.signingRollout.defaultInUseSigningAlgorithms);
        expect(posture.retrofitAuthenticationAlgo,
            posture.signingRollout.defaultRetrofitAuthenticationAlgo,
            reason: 'the retrofit algorithm derives from the stage too — it '
                'was a stored field until 2026-08-14, which is two controls '
                'over one position');
      }
    });

    test('rollout1 is reachable — a client can state the fleet has upgraded',
        () {
      // It cannot come from a posture: there are two postures and no general
      // constructor, so without the preference argument this value would name
      // a rollout position nothing could ever be in.
      final preference =
          AtClientPreference(signingRollout: SigningRollout.rollout1);

      expect(preference.signingRollout, SigningRollout.rollout1);
      expect(preference.inUseSigningAlgorithms, {SigningAlgoType.rsa2048},
          reason: 'and the stage supplies its set, so the enrollment holds a '
              'signing key of its own from birth');
    });

    test('an explicit stage beats the posture, and an explicit set beats both',
        () {
      expect(
          AtClientPreference(
                  posture: const PqPosture.migration(),
                  signingRollout: SigningRollout.rollout2)
              .inUseSigningAlgorithms,
          {SigningAlgoType.mldsa65},
          reason: 'the stage supplies the set when the app names no set');
      expect(
          AtClientPreference(
                  signingRollout: SigningRollout.rollout2,
                  inUseSigningAlgorithms: const {SigningAlgoType.rsa2048})
              .inUseSigningAlgorithms,
          {SigningAlgoType.rsa2048},
          reason: 'the set is what the client obeys — naming both is naming a '
              'mixture on purpose');
    });
  });

  group('the in-use signing set', () {
    test('follows the posture, and an explicit set beats it both ways', () {
      expect(AtClientPreference().inUseSigningAlgorithms, isEmpty);
      expect(
          AtClientPreference(posture: const PqPosture.postQuantum())
              .inUseSigningAlgorithms,
          {SigningAlgoType.mldsa65});
      expect(
          AtClientPreference(
                  posture: const PqPosture.postQuantum(),
                  inUseSigningAlgorithms: const {})
              .inUseSigningAlgorithms,
          isEmpty);
      expect(
          AtClientPreference(
              inUseSigningAlgorithms: const {
                SigningAlgoType.rsa2048
              }).inUseSigningAlgorithms,
          {SigningAlgoType.rsa2048});
    });

    test('refuses an algorithm this build cannot sign an envelope under', () {
      // The refusal is at construction rather than at signing time: an app
      // that asked for a post-quantum signature and was quietly given a
      // classical one has no way to notice.
      expect(
          () => AtClientPreference(
              inUseSigningAlgorithms: const {SigningAlgoType.ecc_secp256r1}),
          throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
              'message', contains('mldsa65, rsa2048'))));
      expect(
          () => AtClientPreference(
              inUseSigningAlgorithms: const {SigningAlgoType.ed25519}),
          throwsArgumentError);
      expect(
          () => AtClientPreference(
              inUseSigningAlgorithms: const {SigningAlgoType.rsa4096}),
          throwsArgumentError);
      // The two this build does sign under, named as literals: a set derived
      // from what canSignEnvelopeWith answers would follow the signer's
      // capability silently, and what an app may ask for is a claim about
      // this release.
      for (final signable in [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048]) {
        expect(
            AtClientPreference(inUseSigningAlgorithms: {signable})
                .inUseSigningAlgorithms,
            {signable});
      }
    });

    test('the set a caller keeps cannot be added to afterwards', () {
      // Final at construction is worth nothing if the contents are not: the
      // check runs once, and a set the caller still holds a reference to
      // would otherwise be a way past it.
      final requested = <SigningAlgoType>{SigningAlgoType.rsa2048};
      final preference =
          AtClientPreference(inUseSigningAlgorithms: requested);
      requested.add(SigningAlgoType.ecc_secp256r1);
      expect(preference.inUseSigningAlgorithms, {SigningAlgoType.rsa2048});
      expect(() => preference.inUseSigningAlgorithms.add(SigningAlgoType.mldsa65),
          throwsUnsupportedError);
    });
  });

  // The envelope shape was a fifth axis here until it stopped being a
  // choice: there is one shape, so a posture has nothing to say about it.
}
