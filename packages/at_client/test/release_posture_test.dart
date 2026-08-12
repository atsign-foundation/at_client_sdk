import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// The rollout posture: the four flags of `docs/projects/pq/decisions.md`
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
    });

    test('postQuantum is the 4.0 column of the rollout table', () {
      const p = ReleasePosture.postQuantum();
      expect(p.writesPqByDefault, true);
      expect(p.disallowLegacyEncryption, true);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(p.retrofitSigningAlgo, SigningAlgoType.mldsa65);
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

  // The envelope shape was a fifth axis here until it stopped being a
  // choice: there is one shape, so a posture has nothing to say about it.
}
