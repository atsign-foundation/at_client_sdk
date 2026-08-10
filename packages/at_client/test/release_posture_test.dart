import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientEnvelopeSigner;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _ClientWith extends Mock implements AtClient {
  final AtClientPreference preference;
  _ClientWith(this.preference);

  @override
  AtClientPreference getPreferences() => preference;
}

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
      expect(p.envelopeVersion, 1);
      expect(p.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);
      expect(p.retrofitSigningAlgo, SigningAlgoType.rsa2048);
    });

    test('postQuantum is the 4.0 column of the rollout table', () {
      const p = ReleasePosture.postQuantum();
      expect(p.writesPqByDefault, true);
      expect(p.disallowLegacyEncryption, true);
      expect(p.envelopeVersion, 2);
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

  group('the envelope version follows the posture unless the signer was told',
      () {
    test('a signer on a postQuantum client emits the JWS shape by default', () {
      final signer = AtClientEnvelopeSigner(_ClientWith(
          AtClientPreference(posture: const ReleasePosture.postQuantum())));
      expect(signer.envelopeVersion, 2);
    });

    test('a signer on a migration client emits version 1 by default', () {
      final signer = AtClientEnvelopeSigner(_ClientWith(AtClientPreference()));
      expect(signer.envelopeVersion, 1);
    });

    test('a per-signer assignment beats the posture, both ways', () {
      final pqSigner = AtClientEnvelopeSigner(_ClientWith(
          AtClientPreference(posture: const ReleasePosture.postQuantum())))
        ..envelopeVersion = 1;
      expect(pqSigner.envelopeVersion, 1);

      final migrationSigner =
          AtClientEnvelopeSigner(_ClientWith(AtClientPreference()))
            ..envelopeVersion = 2;
      expect(migrationSigner.envelopeVersion, 2);
    });

    test('a client with no preference at all emits version 1', () {
      final signer = AtClientEnvelopeSigner(MockAtClient());
      expect(signer.envelopeVersion, 1,
          reason: 'the fallback when nothing supplies a posture is the 3.x '
              'wire default, never the new shape');
    });
  });
}

class MockAtClient extends Mock implements AtClient {}
