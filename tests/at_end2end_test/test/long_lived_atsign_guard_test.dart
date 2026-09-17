/// The guard that keeps post-quantum state off this suite's long-lived
/// atSigns.
///
/// `@ce2e1`..`@ce2e4` are real atServers on root.atsign.wtf that no run
/// recycles, and their keyfiles are repository secrets a workflow cannot
/// rewrite. A retrofit **caps** the enrollment it replaces rather than
/// deleting it, and a published namespace key is what every peer then seals
/// to — so a mis-postured client there does not fail, it arms a failure for
/// somewhere else later.
///
/// Pure local inspection; it talks to no atServer.
library;

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';

void main() {
  const protectedAtSign = '@ce2e1';
  const throwawayAtSign = '@alice🛠';

  void check(String atSign, AtClientPreference preference) =>
      TestPreferences.refuseDurableWritesToLongLivedAtSigns(atSign, preference);

  test('the legacy posture is allowed there', () {
    expect(
        () => check(
            protectedAtSign, AtClientPreference(posture: PqPosture.legacy)),
        returnsNormally,
        reason: 'the whole suite runs at this posture; a guard that refused it '
            'would refuse every non-PQ test');
  });

  test('a post-quantum posture is refused there', () {
    expect(
        () => check(
            protectedAtSign, AtClientPreference(posture: PqPosture.pqReady)),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('RETROFIT'), contains(protectedAtSign)))),
        reason: 'this posture authenticates with ML-DSA, which is stronger '
            'than the RSA enrollment these atSigns hold, so the next start '
            'would retrofit and cap the enrollment CI depends on');
  });

  test('the shipped default no longer reaches that case, and is allowed', () {
    expect(() => check(protectedAtSign, AtClientPreference()), returnsNormally,
        reason: 'the shipped default drives no retrofit, seeds nothing and '
            'runs no post-quantum startup, so it writes nothing to these '
            'atSigns that outlives the run');
  });

  test('a throwaway atSign is not restricted', () {
    // NOTE: the posture has to be named — the default `legacy` is allowed on
    // any atSign, so a bare preference would pass whatever the guard did.
    expect(
        () => check(
            throwawayAtSign, AtClientPreference(posture: PqPosture.pqReady)),
        returnsNormally,
        reason: 'a local run generates demo atSigns and discards the '
            'virtualenv, so the guard must not fire there — otherwise the PQ '
            'tests could not run at all');
  });

  group('it checks the axes, not the posture', () {
    test('a legacy posture with a stronger authentication key still refuses',
        () {
      expect(
          () => check(protectedAtSign, AtClientPreference(
              posture: PqPosture.legacy,
              authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
              // NOTE: must be non-empty, or the constructor rejects the
              // non-rsa2048 authentication key and this throws at
              // construction instead of reaching the guard.
              dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('RETROFIT'))),
          reason: 'retrofitIsDue reads authenticationKeyAlgorithm, not the '
              'posture — a guard keyed on the posture name would wave this '
              'through and the enrollment would be capped');
    });

    test('a legacy posture minting signing keys still refuses', () {
      expect(
          () => check(
              protectedAtSign,
              AtClientPreference(
                  posture: PqPosture.legacy,
                  dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('mint signing keys'))),
          reason: 'a non-empty in-use set mints keys and advertises them in '
              '_apsk, which outlives the run');
    });

    test('seeding turned on after construction still refuses', () {
      // NOTE: seedNamespaceKeys stays assignable after construction; the guard
      // catches it because it runs at the point of use.
      final preference = AtClientPreference(posture: PqPosture.legacy)
        ..seedNamespaceKeys = true;
      expect(
          () => check(protectedAtSign, preference),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('publish a namespace key'))),
          reason: 'a published nskey is what peers seal to, and nothing here '
              'rotates one back out');
    });
  });

  test('the helper itself refuses, not just the check in isolation', () {
    expect(
        () => TestPreferences.getInstance()
            .getPreference(protectedAtSign, posture: PqPosture.pqReady),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains(protectedAtSign))),
        reason: 'getPreference is where all but one of this pack\'s clients '
            'get their preference; a guard it did not call would be a rule '
            'nothing enforces');
  });

  test('no test reaches a live client around the guarded doors', () {
    // The rule: a file may construct an AtClientPreference only if it also
    // invokes the guard, since the guard can only refuse what passes through
    // it.
    final offenders = <String>[];
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('AtClientPreference(')) continue;
      if (source.contains('refuseDurableWritesToLongLivedAtSigns')) continue;
      offenders.add(entity.path);
    }
    expect(offenders, isEmpty,
        reason: 'these files build an AtClientPreference of their own and '
            'never invoke the guard, so they can reach a live client without '
            'it: $offenders. Either take the preference from '
            'TestPreferences.getPreference, or call '
            'TestPreferences.refuseDurableWritesToLongLivedAtSigns on what you '
            'built before handing it to a client.');
  });

  test('every atSign the CI configs name is covered by the guard', () {
    // NOTE: whichever of the two survives, not both — CI renames one to
    // config.yaml before it runs. Either is enough, as they name the same
    // atSigns in a different order.
    final configs = ['config14.yaml', 'config23.yaml']
        .map((name) => File('config/$name'))
        .where((file) => file.existsSync())
        .toList();
    expect(configs, isNotEmpty,
        reason: 'neither config14.yaml nor config23.yaml is present, so this '
            'guard is checking nothing. CI moves ONE of them to config.yaml; '
            'if both have gone, they have been renamed or removed and the '
            'atSign set here has nothing left to be checked against');

    final named = <String>{};
    for (final file in configs) {
      for (final match in RegExp(r"'(@[A-Za-z0-9_]+)'")
          .allMatches(file.readAsStringSync())) {
        named.add(match.group(1)!);
      }
    }
    expect(named, isNotEmpty,
        reason: 'no atSign parsed out of the configs, so the comparison below '
            'would pass against an empty set');
    expect(TestPreferences.longLivedAtSigns.containsAll(named), isTrue,
        reason: 'these atSigns are named by a CI config and are not in '
            'TestPreferences.longLivedAtSigns, so nothing stops a test '
            'retrofitting them: ${named.difference(TestPreferences.longLivedAtSigns)}');
  });
}
