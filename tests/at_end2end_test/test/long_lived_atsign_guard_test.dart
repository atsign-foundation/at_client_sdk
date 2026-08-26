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
/// Pinning `PqPosture.legacy` at every call site is a convention, and a
/// convention is what this file exists to replace. Pure local inspection; it
/// talks to no atServer.
library;

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';

void main() {
  const protectedAtSign = '@ce2e1';
  const throwawayAtSign = '@alice🛠';

  /// The guard reads a built preference, so each case builds the real thing
  /// rather than a stub — a stub would prove the matcher, not the rule.
  void check(String atSign, AtClientPreference preference) =>
      TestPreferences.refuseDurableWritesToLongLivedAtSigns(atSign, preference);

  // The negative control comes first on purpose: without it, a guard that
  // threw unconditionally would pass every other test in this file.
  test('the legacy posture is allowed there', () {
    expect(
        () => check(
            protectedAtSign, AtClientPreference(posture: PqPosture.legacy)),
        returnsNormally,
        reason: 'the whole suite runs at this posture; a guard that refused it '
            'would refuse every non-PQ test');
  });

  test('the shipped default is refused there', () {
    // A bare preference takes the SDK default, which is what an unwitting new
    // test would get by naming nothing — the exact case the guard is for.
    expect(
        () => check(protectedAtSign, AtClientPreference()),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('RETROFIT'), contains(protectedAtSign)))),
        reason: 'the default posture authenticates with ML-DSA, which is '
            'stronger than the RSA enrollment these atSigns hold, so the next '
            'start would retrofit and cap the enrollment CI depends on');
  });

  test('a throwaway atSign is not restricted', () {
    expect(() => check(throwawayAtSign, AtClientPreference()), returnsNormally,
        reason: 'a local run generates demo atSigns and discards the '
            'virtualenv, so the guard must not fire there — otherwise the PQ '
            'tests could not run at all');
  });

  group('it checks the axes, not the posture', () {
    // The point of the whole guard. Every axis below is settable BESIDE a
    // posture, so `posture == PqPosture.legacy` is a weaker test than it looks
    // and would pass each of these.
    test('a legacy posture with a stronger authentication key still refuses',
        () {
      expect(
          () => check(
              protectedAtSign,
              AtClientPreference(
                  posture: PqPosture.legacy,
                  authenticationKeyAlgorithm: SigningAlgoType.mldsa65)),
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
      // seedNamespaceKeys is the one axis that stays assignable, so a test
      // could flip it on a preference the guard had already accepted. The
      // guard runs at the point of use, which is why that is caught.
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
    // Every test above calls the guard directly, which proves the rule and
    // says nothing about whether anything invokes it. This one goes through
    // the door the suite actually uses.
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
    // The guard can only refuse what passes through it. Three doors reach a
    // live client in this pack — TestPreferences.getPreference, the
    // initialiser, and the isolate-local builder in notify_with_isolate_test —
    // and every one of them calls the guard. A file that BUILT its own
    // preference and called setCurrentAtSign itself would go round all three,
    // and nothing else would notice. So: a file may construct an
    // AtClientPreference only if it also invokes the guard.
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
    // The set cannot be allowed to drift from the configs it protects: adding
    // a fifth atSign to a config without adding it here would leave that one
    // unguarded, and nothing else would notice.
    final named = <String>{};
    for (final name in ['config14.yaml', 'config23.yaml']) {
      final file = File('config/$name');
      expect(file.existsSync(), isTrue,
          reason: 'config/$name is what CI moves into place; if it has been '
              'renamed this guard is checking nothing');
      for (final match
          in RegExp(r"'(@[A-Za-z0-9_]+)'").allMatches(file.readAsStringSync())) {
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
