import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:test/test.dart';

/// `AtOnboardingPreference` can carry the flags its superclass fixes at
/// construction.
///
/// Every one of them is `final` in `AtClientPreference` — deliberately, since
/// what a client writes must not change meaning mid-run — and this class
/// declared no constructor, so a CLI application could neither pass them nor
/// assign them afterwards. `at_cli_commons`' `CLIBase` takes a preference and
/// falls back to `AtOnboardingPreference()`, so the whole CLI fleet inherited
/// the default and had no way off it.
void main() {
  group('AtOnboardingPreference forwards the construction-final flags', () {
    test('the no-arg form still means what it always did', () {
      // The compatibility arm. Every parameter is optional, so the call every
      // existing consumer makes must land on the superclass defaults.
      final defaults = AtClientPreference();
      final preference = AtOnboardingPreference();

      expect(preference.rolloutDifferencesFrom(defaults), isEmpty,
          reason: 'asserted through the SDK\'s own axis-by-axis comparison '
              'rather than field by field, so an axis added later is covered '
              'without this test being edited');
    });

    test('a posture given here reaches the client behaviour it implies', () {
      final preference =
          AtOnboardingPreference(posture: PqPosture.pqActive);

      expect(preference.posture.writesPqByDefault, isTrue);
      expect(preference.disallowLegacyEncryption, isTrue,
          reason: 'the posture supplies the flag defaults, so forwarding the '
              'posture alone has to move them too — a constructor that took '
              'the argument and dropped it would still pass the line above');
    });

    test('and each axis can be named against the posture that implies it', () {
      // The mixture case the superclass documents: an explicitly set axis
      // beats the group it came from. Without forwarding there was no way to
      // express it at all from a CLI app.
      // A signing set weaker than the posture is deliberately still allowed:
      // pqActive with {rsa2048} mints rsa2048 and keeps `_apsk` bare, which is
      // coherent. It is the AUTHENTICATION axis that may not be lowered.
      final preference = AtOnboardingPreference(
        posture: PqPosture.pqActive,
        dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048},
      );

      expect(preference.dataSigningKeyAlgorithms, {SigningAlgoType.rsa2048},
          reason: 'the explicitly set axis beats the group it came from, and '
              'without forwarding there was no way to express it at all from '
              'a CLI app');
      expect(preference.authenticationKeyAlgorithm, SigningAlgoType.mldsa65,
          reason: 'while the axis nobody named stays where the posture put it');
      expect(preference.disallowLegacyEncryption, isTrue,
          reason: 'and the one axis with no override stays where the posture '
              'put it, however many of its neighbours are named');
    });

    test('and the superclass\'s coherence rules see the forwarded axis', () {
      // ⛔ This construction was pinned as supported until 2026-08-30, with the
      // reason 'a deployment whose atServer cannot verify ML-DSA PKAM yet says
      // so here without giving up the rest of the stage'. No such deployment
      // has a holder. A posture is a floor.
      //
      // What it proves now is sharper than what it proved then: the refusal
      // comes from AtClientPreference, so a subclass that accepted the argument
      // and dropped it would construct happily and go unnoticed here.
      expect(
          () => AtOnboardingPreference(
                posture: PqPosture.pqActive,
                authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
                dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048},
              ),
          throwsA(isA<ArgumentError>()));
    });

    test('the mutable fields are untouched by the new constructor', () {
      // The constructor deliberately forwards only what is final. Anything
      // assignable stays assignable, and a constructor that had shadowed one
      // would break every consumer that sets it after the fact.
      final preference = AtOnboardingPreference()
        ..namespace = 'my_app'
        ..seedNamespaceKeys = true
        ..atKeysFilePath = '/tmp/@alice_key.atKeys';

      expect(preference.namespace, 'my_app');
      expect(preference.seedNamespaceKeys, isTrue,
          reason: 'set away from its false default, or the assertion would '
              'hold for a field nothing wrote');
      expect(preference.atKeysFilePath, '/tmp/@alice_key.atKeys');
    });
  });
}
