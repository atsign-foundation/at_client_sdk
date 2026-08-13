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
      const p = ReleasePosture.migration();
      expect(p.writesPqByDefault, false);
      expect(p.disallowLegacyEncryption, false);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);
      expect(p.retrofitSigningAlgo, SigningAlgoType.rsa2048);
      expect(p.inUseSigningAlgorithms, isEmpty,
          reason: 'an enrollment holding a signing key of its own holds two '
              'keys, and two keys cannot be advertised as the bare public key '
              'string every deployed reader understands');
    });

    test('postQuantum is the 4.0 column of the rollout table', () {
      const p = ReleasePosture.postQuantum();
      expect(p.writesPqByDefault, true);
      expect(p.disallowLegacyEncryption, true);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(p.retrofitSigningAlgo, SigningAlgoType.mldsa65);
      expect(p.inUseSigningAlgorithms, {SigningAlgoType.mldsa65},
          reason: 'ML-DSA alone: a verifier takes the strongest algorithm the '
              'envelope and the advertisement share, so a second, weaker key '
              'would cost a signature per envelope to be passed over');
    });
  });

  group('the preference applies the posture at construction', () {
    test('a bare preference runs the migration posture', () {
      final preference = AtClientPreference();
      expect(preference.posture, same(const ReleasePosture.migration()),
          reason: 'the 3.x defaults are the defaults — an app that names '
              'nothing rides the SDK\'s own migration schedule');
      expect(preference.disallowLegacyEncryption, false);
    });

    test('postQuantum sets disallowLegacyEncryption', () {
      final preference =
          AtClientPreference(posture: const ReleasePosture.postQuantum());
      expect(preference.disallowLegacyEncryption, true);
    });

    test('an explicit disallowLegacyEncryption beats the posture, both ways',
        () {
      expect(
          AtClientPreference(
                  posture: const ReleasePosture.postQuantum(),
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

  group('the in-use signing set', () {
    test('follows the posture, and an explicit set beats it both ways', () {
      expect(AtClientPreference().inUseSigningAlgorithms, isEmpty);
      expect(
          AtClientPreference(posture: const ReleasePosture.postQuantum())
              .inUseSigningAlgorithms,
          {SigningAlgoType.mldsa65});
      expect(
          AtClientPreference(
                  posture: const ReleasePosture.postQuantum(),
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
