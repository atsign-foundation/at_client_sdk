import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part C — the rollout, driven by flags (`acceptance.md` section 15).
///
/// The capstone of the rollout-posture design (`decisions.md` 56.4): 4.0 is
/// final-3.x code with different flag defaults, so the entire rollout must be
/// drivable from this codebase by flag manipulation — each axis in isolation,
/// and all of them at once as the grouped `PqPosture`. (Not "all seven": the
/// count was correct when written and an eighth axis was added the same day.
/// Re-derive from the type rather than restating a number.)
///
/// The envelope-shape axis (UC-C1.3) is gone because the envelope stopped
/// having a second shape to roll out to, so there was no axis left to drive;
/// the in-use signing set (UC-C1.7) took the vacated fifth slot. The count is
/// five by coincidence rather than because the original five stand.
void main() {
  test('UC-C1.1 · the era axis: a postured client writes PQ by default', () {
    // GIVEN a client built with PqPosture.pqActive and no
    //       app-named crypto config.
    // WHEN  its era CryptoConfig is adopted at construction.
    // THEN  new writes default to the nskey data path (AES-GCM provider),
    //       while a migration-postured client's stay legacy — and an
    //       app-named config still beats both.
    provenIn('packages/at_client/test/at_client_impl_test.dart',
        'the pqActive posture makes PQ writes the adopted era default',
        proves: 'the 4.0 arm: era default flips to the nskey data path',
        clauses: [
          'new writes default to the nskey data path (the AES-GCM provider)',
        ]);
    provenIn('packages/at_client/test/at_client_impl_test.dart',
        'the legacy posture keeps writes legacy in the adopted era set',
        proves: 'the 3.x arm: same provider set, writes stay legacy');
    provenIn('tests/at_functional_test/test/pq_stage_arm_test.dart',
        'UC-C1.1 · the era default follows the stage on a live client',
        proves: 'all three stages side by side on real clients: the middle '
            'stage still writes legacy, which is what makes it a stage of its '
            'own rather than a name for the last one');
    provenIn('tests/at_functional_test/test/pq_stage_arm_test.dart',
        'each stage reaches its own constructed client',
        proves: 'the Given the arm rests on — that the posture survives '
            'enrolment and construction, so the rows above are about the '
            'stage rather than about a default');
  });

  test('UC-C1.2 · the refusal axis: the posture disallows legacy writes', () {
    // GIVEN a preference built with PqPosture.pqActive.
    // WHEN  a write would fall back to the legacy provider.
    // THEN  it is refused (LegacyEncryptionRefusedException), because the
    //       posture set the flag — and nothing but a posture can set it.
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'pqActive sets disallowLegacyEncryption',
        proves: 'the posture reaches the flag');
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'disallowLegacyEncryption has no per-preference override',
        proves: 'the deliberate exception to the per-axis override contract');
    provenIn('packages/at_client/test/disallow_legacy_encryption_test.dart',
        'the only way to set it is a posture that writes post-quantum',
        proves: 'the coupling: a posture asking for the refusal must write '
            'post-quantum, or it refuses its own writes');
    provenIn('packages/at_client/test/disallow_legacy_encryption_test.dart',
        'a client configured to write legacy',
        proves: 'what the flag does once set: the legacy write is refused');
    // The four above are unit arms against a mock, which never runs
    // AtClientImpl's initialisation — so a posture that reached the constant
    // and never reached a client would satisfy all of them. These two are the
    // first live proof this row has had.
    provenIn('tests/at_functional_test/test/pq_stage_arm_test.dart',
        'UC-C1.2 · pqActive refuses a legacy write that the earlier stages take',
        proves: 'the refusal on a real constructed client, with the two '
            'earlier stages taking the identical write as controls — so the '
            'refusal is caused by the stage and not by the key',
        clauses: [
          'because the posture set the flag',
        ]);
    provenIn('tests/at_functional_test/test/pq_stage_arm_test.dart',
        'UC-C1.2 · the refusal fires through a real put, not only at selection',
        proves: 'the guarantee holds through the put pipeline, not merely at '
            'provider selection');
  });

  test('UC-C1.4 · the key-exchange axis: the posture names pq enrollment', () {
    // GIVEN a submitter composing an AtEnrollmentRequest under
    //       PqPosture.pqActive (at_auth cannot read a preference,
    //       so the posture's value is applied by whoever builds the request).
    // WHEN  the request is submitted with keyExchangeMode = pq.
    // THEN  no RSA-wrapped apkamSymmetricKey rides the wire; the approver
    //       mints and conveys instead.
    //
    // ⚠️ **This row read PROVEN while NOBODY applied the posture's value.**
    // The citations below prove the two ends — the posture carries the mode,
    // and at_auth honours the mode when it is given one — and until
    // 2026-08-26 nothing joined them: `at_onboarding_cli`, the only production
    // caller that submits an app enrolment, built the unnamed
    // `AtEnrollmentRequest(...)`, whose initialiser hard-sets `legacy`. The
    // GIVEN above names the gap honestly ("applied by whoever builds the
    // request") and no citation covered that clause. Found by the citation
    // audit; the first citation below is now that middle.
    provenIn(
        'packages/at_onboarding_cli/test/enroll_key_exchange_mode_test.dart',
        'PqPosture.pqActive submits a pq request',
        proves: 'the middle the other three do not reach: a real production '
            'builder reading a posture and choosing the constructor from it. '
            'The request captured off the AtEnrollment seam under '
            'PqPosture.pqActive carries EnrollmentKeyExchangeMode.pq and both '
            'the callbacks a pq request needs, where the same service under '
            'PqPosture.legacy submits the wrapped-key shape. Mutating the '
            'service to keep the unnamed constructor reddens it.');
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'pqActive is post-quantum by default',
        proves: 'the posture carries EnrollmentKeyExchangeMode.pq');
    provenIn('packages/at_auth/test/enrollment_test.dart',
        'pq mode sends no RSA-wrapped symmetric key',
        proves: 'what the mode does on the wire',
        clauses: [
          'rides the wire; the approver mints and conveys instead',
        ]);
    provenIn('packages/at_auth/test/enrollment_test.dart',
        'the default mode is legacy',
        proves: 'the 3.x wire stays byte-identical until a posture or the '
            '4.x major flips it');
  });

  test('UC-C1.5 · the retrofit axis: an argless retrofit follows the posture',
      () {
    // GIVEN a legacy atSign and a preference carrying PqPosture.pqActive.
    // WHEN  selfRetrofit runs with no signingAlgo argument.
    // THEN  the minted enrollment is ML-DSA — under the legacy posture the
    //       same call mints RSA, which is what tells the two apart live.
    provenIn(
        'tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart',
        'the pqActive posture decides an argless retrofit',
        proves: 'the pqActive half, against a real atServer: an argless '
            'selfRetrofit on a keyfile of its own comes back with '
            'signingAlgoOf == mldsa65, which is the authentication algorithm '
            'the resulting client resolves from that keyfile — nothing in the '
            'arm named an algorithm, so the posture is the only thing that '
            'could have chosen it',
        clauses: [
          'the minted enrollment is ML-DSA',
        ]);
    provenIn(
        'tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart',
        'an argless retrofit under the default preference stays rsa2048',
        proves: 'the legacy half of the same clause, which is what makes the '
            'first half mean something: the identical argless call under the '
            'legacy posture resolves rsa2048. A consult replaced by a '
            'constant passes the ML-DSA arm and fails this one',
        clauses: [
          'the minted enrollment is ML-DSA',
        ]);
  });

  test('UC-C1.6 · the grouped posture: one value sets every axis', () {
    // GIVEN nothing but AtClientPreference(posture: PqPosture.pqActive).
    // WHEN  a client, its signers, its enrollment submissions and its
    //       retrofits are built from that one preference.
    // THEN  every axis runs the last stage's values — the pinned columns of
    //       ruling 113's table — with each still individually overridable
    //       (C1.1–C1.5 prove each arm).
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'pqActive is post-quantum by default',
        proves: 'every axis of the last stage, pinned as literals');
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'legacy drives no upgrade',
        proves: 'the stage an app names to opt OUT is a contract too, not an '
            'accident — it is what makes a compatibility test possible');
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'a bare preference runs the pqReady posture',
        proves: 'what an app that names nothing gets, pinned as a literal, so '
            'moving the shipped default is an edit to that test and the edit '
            'is the review');
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'disallowLegacyEncryption has no per-preference override',
        proves: 'the one axis the posture alone moves, which is what this row '
            'used to deny: the flag is false by default and under pqReady, '
            'true under pqActive, and naming the other axes explicitly '
            'alongside pqActive does not move it. There is no constructor '
            'argument to try, so what is asserted is that no combination of '
            'the arguments that DO exist changes it',
        clauses: [
          'except `disallowLegacyEncryption`, which the posture alone moves'
        ]);
  });

  test('UC-C1.7 · the signing-set axis: which keys an enrollment holds', () {
    // GIVEN a preference built with PqPosture.pqActive and no
    //       explicit dataSigningKeyAlgorithms argument.
    // WHEN  the set is read.
    // THEN  it is {mldsa65}, while a legacy-postured preference's is empty
    //       — an enrollment that mints no signing key of its own keeps signing
    //       with its APKAM authentication key. An explicit argument wins both
    //       ways, and an algorithm this build cannot sign under is refused
    //       where it is named.
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'pqActive is post-quantum by default',
        proves: 'the last stage\'s default, pinned as a literal: {mldsa65}');
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'legacy drives no upgrade',
        proves: 'the default stage\'s set is empty — no client mints until '
            'the posture says so');
    // The two below are in that file's "the data signing set" group.
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'follows the posture, and an explicit set beats it both ways',
        proves: 'the per-axis override contract, in both directions',
        clauses: [
          'an enrollment that mints no signing key of its own keeps signing '
              'with its APKAM authentication key',
        ]);
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'refuses an algorithm this build cannot sign an envelope under',
        proves: 'the refusal is at construction, where the algorithm is named');
    // And the middle stage, which is where the two key axes come apart.
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'pqReady moves the credentials and not the data path',
        proves: 'the middle stage, pinned as literals: an ML-DSA '
            'authentication key beside an rsa2048 data signing key');
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'it is a separate axis from the data signing keys',
        proves: 'the two keys are not one stage name — the whole reason the '
            'middle stage exists');
  });
}
