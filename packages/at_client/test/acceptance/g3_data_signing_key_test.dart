import 'package:test/test.dart';

import 'blockers.dart';
import 'proven_elsewhere.dart';

/// Part G3 — the data signing key an enrollment owns from birth
/// (`acceptance.md` section 18).
void main() {
  test(
      'UC-G3.1 · every creation door files the private half, not just the '
      'public one', () {
    provenIn('packages/at_auth/test/enrollment_test.dart',
        'the signing key is FILED, not merely advertised',
        proves: 'the enrolment door — the request carries the key, and after '
            'submit the keyfile HOLDS its private half. A test that only read '
            'the built command would be green for a key that reached the wire '
            'and never reached disk, which is the exact failure the filing '
            'exists to prevent',
        clauses: ['is written to the keyfile as typed']);
    provenIn('packages/at_auth/test/enrollment_test.dart',
        'without one, nothing is filed',
        proves: 'the control. Without it the assertion above is satisfied by '
            'a path that files something unconditionally, and the filing '
            'would not be attributable to the advertised key at all',
        clauses: ['files nothing, so the filing is attributable']);
    provenIn('packages/at_auth/test/enrollment_test.dart',
        'and it is the ENROLLMENT\'s, not the atSign\'s',
        proves: 'the id it is filed under. Filing into the atSign\'s own '
            'container would leave signingKeysFor(enrollmentId) empty, so the '
            'next start would find the algorithm missing and mint a second '
            'keypair — advertised-but-not-filed by another route',
        clauses: ['under the id the atServer assigned']);
    provenIn('packages/at_auth/test/at_self_enrollment_test.dart',
        'the signing key is FILED, not merely advertised',
        proves: 'the self-retrofit door, which files at a different site in '
            'at_auth (inside the serialised critical section, against the '
            'EXISTING keyfile) and could regress independently of the one '
            'above');
    provenIn('packages/at_auth/test/pq_native_onboard_test.dart',
        'the PRIVATE half reaches the keyfile, under the enrollment id',
        proves: 'the third door — a PQ-native ACTIVATION — which nothing '
            'covered until 2026-08-31. It drives AtAuthImpl.onboard end to '
            'end, so it is the FILING rather than the request: '
            'packages/at_client/test/pq_native_onboard_test.dart asserts the '
            'activation CARRIES the key, which is a claim about the request '
            'object, and what reaches the keyfile is whatever at_auth copies '
            'out of it after the atServer answers. The enrollment id it reads '
            'back under appears nowhere in the request — the mock returns it — '
            'so a non-empty answer also establishes that the ASSIGNED id was '
            'used. Three mutations, one per assertion: dropping the filing, '
            'swapping the private half for the public one, and taking the '
            'algorithm from the APKAM instead of from the key',
        clauses: ['is written to the keyfile as typed']);
  });

  test(
      'UC-G3.2 · the algorithm minted is the one kept, so the first start '
      'rewrites nothing', () {
    provenIn('packages/at_client/test/signing_key_mint_test.dart',
        'pqReady mints rsa2048',
        proves: 'the pqReady half of "the algorithm minted is the one the '
            'enrollment keeps" — read off the posture rather than off a '
            'constant, so a posture whose set changed would move this');
    provenIn('packages/at_client/test/signing_key_mint_test.dart',
        'pqActive mints mldsa65',
        proves: 'the pqActive half, which is the one that matters: minting '
            'rsa2048 there would leave the first start finding ML-DSA missing '
            'and republishing the record the enrolment just created');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'an algorithm already held is not minted again',
        proves: 'the no-op itself, and specifically that NOTHING IS PUBLISHED '
            '— it asserts the update list is empty, not merely that the '
            'minted list is. A reconcile that republished an unchanged value '
            'would satisfy "mints nothing" and still rewrite the record, '
            'which is what breaks a conveyed link',
        clauses: ['mints no key, retires none']);
    provenIn('packages/at_client/test/signing_key_mint_test.dart',
        'a set naming two algorithms',
        proves: 'the refusal, rather than a silent choice between them',
        clauses: ['a set naming more than one algorithm']);
  });

  test(
      'UC-G3.3 · the _apsk form follows the algorithm, and nothing else '
      'decides it', () {
    provenIn('packages/at_client/test/apkam_signing_keys_test.dart',
        'republishes when the published value is not what it holds',
        proves: 'the republish-on-any-difference half, with its sibling '
            'writes nothing when the published value already matches as the '
            'control that makes it a discriminator',
        clauses: ['rewrites the record at the client']);
    provenIn('packages/at_auth/test/enrollment_test.dart',
        'an rsa2048 APKAM key with a key package is spelled BARE',
        proves: 'the at_auth side, in the shape that was WRONG until '
            '2026-08-31: a key package present alongside an rsa2048 key. That '
            'combination forced the array, so a legacy-posture pq-key-exchange '
            'enrolment was created with an advertisement its own client '
            'rewrote at first start',
        clauses: ['both spell anything else as the']);
    provenIn('packages/at_auth/test/enrollment_test.dart',
        'an mldsa65 APKAM key with a key package is spelled as the ARRAY',
        proves: 'the control on the same axis — without it the row above is '
            'satisfied by a composer that can only ever emit the bare form');
    provenIn('packages/at_client/test/apsk_formats_test.dart',
        'one active rsa2048 key is spelled bare, not as the array',
        proves: 'the at_client side of the same rule, so the two composers '
            'are pinned against the same statement rather than each against '
            'its own');
    provenIn('packages/at_client/test/apsk_formats_test.dart',
        'a second key forces the array',
        proves: 'the at_client control, for the same reason as the at_auth '
            'one');

    provenIn('tests/at_functional_test/test/apsk_server_side_test.dart',
        'a healed enrollment advertises its signing key in the bare form',
        proves: 'the at_client half of the spelling against a REAL atServer — '
            'the record is fetched back and is the key itself, not a '
            'one-entry array. Deliberately UNPINNED: it establishes what '
            'at_client publishes and says nothing about what at_auth writes '
            'at enrolment, so pinning the clause with it would record both '
            'composers as server-proven when only one is');

    // NOTE: the "no second condition" clause asserts an absence, which no test
    // can pin; the citations above establish only that the two composers agree.
  });

  test(
      'UC-G3.5 · an approver links each key of the enrollment it approves, '
      'straight after approving', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.6 · a legacy enrollment\'s authentication keypair signs data in '
      'memory only', () {
    provenIn('packages/at_client/test/apkam_signing_keys_test.dart',
        'falls back to the APKAM authentication keypair with no key source',
        proves: 'the fallback is built from atChops rather than read from the '
            'keyfile — this client has no key source at all, so nothing could '
            'have been filed for it to find',
        clauses: ['built from `atChops` on the call']);
    provenIn('packages/at_client/test/apkam_signing_keys_test.dart',
        'the keyfile\'s signing material wins over the authentication keypair',
        proves: 'the control: the fallback is a fallback, not a preference');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'the advertisement names the minted key and drops the auth key',
        proves: 'the two halves moving TOGETHER — the advertisement stops '
            'naming the authentication key in the same step that the '
            'enrollment starts holding one of its own. What signs and what is '
            'advertised are one rule, and this is where they are pinned as '
            'one',
        clauses: ['stops signing and stops being advertised in the same step']);
    provenIn('packages/at_client/test/apkam_signing_keys_test.dart',
        'an enrollment holding its own authentication keypair publishes bare',
        proves: 'the advertisement half on its own: the authentication key is '
            'the sole ACTIVE entry while the enrollment holds no signing key');
  });

  test(
      'UC-G3.7 · the reconcile treats rsa2048 as already held, and only '
      'rsa2048', () {
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'so an in-use set naming rsa2048 mints nothing',
        proves: 'the correction itself — one keypair doing both jobs is not a '
            'missing key, and minting a second rsa2048 keypair would publish '
            'it and DROP the original from _apsk',
        clauses: ['a second rsa2048 keypair buys nothing']);
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'an ML-DSA-authenticating enrollment holding none still mints one',
        proves: 'the scope, and it is the assertion this row exists for. An '
            'exclusion keyed on whatever algorithm the authentication keypair '
            'reports would fire here, mint no ML-DSA signing key ever, and '
            'advertise the authentication key as the sole active entry — the '
            'auth/signing split collapsing on the posture that exists to '
            'create it, with nothing else going red',
        clauses: ['which is the whole of its correctness']);
    provenIn('tests/at_functional_test/test/apsk_server_side_test.dart',
        'a healed enrollment advertises its signing key in the bare form',
        proves: 'the control arm LIVE, and it is the same shape: an '
            'enrollment authenticating with ML-DSA-65 that holds no typed '
            'signing material reconciles against a real atServer, mints '
            'rsa2048, and the record it publishes reads back as the bare key. '
            'The unit arm proves the decision; this proves the atServer '
            'accepts what the decision produces, which is a separate claim — '
            'the advertisement travels by enroll:update, a verb that had only '
            'ever carried apskLegacy on the enrolment request',
        clauses: ['which is the whole of its correctness']);
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'and a legacy enrollment at pqActive mints ML-DSA too',
        proves: 'the same scope read from the posture rather than from the '
            'algorithm, so a change to either would break one of the two',
        clauses: ['still mints ML-DSA, and a retrofitted enrollment']);
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'and a RETROFITTED enrollment still mints rsa2048',
        proves: 'the third shape: typed APKAM material under a new enrollment '
            'id, holding no signing key. It is not the legacy shape and must '
            'not inherit the legacy answer');
  });

  test('UC-G3.8 · no signer waits on a mint', () {
    provenIn('packages/at_client/test/apkam_signing_keys_test.dart',
        'it returns while a startup step is still parked',
        proves: 'the absence of the barrier, asserted as a BOUND rather than '
            'as a shape: the call is given five seconds and fails by name if '
            'it does not answer. Nothing in the test settles anything, which '
            'is what makes the answer attributable to the signer rather than '
            'to the fixture. The deadlock it replaces cost eight runs of '
            '`at_activate approve` overrunning a two-minute bound with '
            'nothing in the log to say why',
        clauses: ['waiting on no other work']);
    provenIn('packages/at_client/test/apkam_signing_keys_test.dart',
        'and it signs with the filed key once one is there',
        proves: 'the control: same call, same signer, and the only difference '
            'is what the keyfile holds — so the fallback answering above is '
            'attributable to the empty keyfile and not to a signer that can '
            'only ever return the authentication key',
        clauses: ['rather than from a cache']);
  });

  test('UC-G3.9 · two coherence rules, refused at construction before any I/O',
      () {
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'follows the posture, and an explicit set beats it both ways',
        proves: 'rule 1 AND its control in one test: an empty set beside '
            'pqActive throws, and the same empty set beside legacy is '
            'accepted. ⛔ It pinned the empty set beside pqActive as SUPPORTED '
            'until 2026-08-30, so the assertion and the thing it replaced are '
            'both visible in the diff',
        clauses: ['authentication key is refused']);
    provenIn('packages/at_client/test/pq_posture_test.dart',
        'but an explicit value may not be WEAKER than the posture',
        proves: 'rule 2. ⚠️ It reads the AUTHENTICATION axis and only that '
            'one: a dataSigningKeyAlgorithms weaker than the posture names '
            'stays legal on purpose, so a test asserting "any axis" would be '
            'asserting a rule the tree does not have',
        clauses: ['weaker than the posture names is refused']);
  });

  test(
      'UC-G3.10 · a no-PQ-provider client refuses the work and leaves the '
      'enrolment repairable', () {
    provenIn('packages/at_client/test/enrollment_conveyance_guard_test.dart',
        'refuses a request that asks it to mint, and leaves it pending',
        proves: 'the ORDER, which is the whole row: the record is still '
            'pending afterwards. A guard that threw after the approval landed '
            'would leave a device authorised and holding none of the material '
            'it was authorised for, and no later approval could repair it '
            'because the request is spent',
        clauses: ['so the record stays pending']);
    provenIn('packages/at_client/test/enrollment_conveyance_guard_test.dart',
        'refuses the unanchored-enrollment sweep',
        proves: 'the second refusal, in the SERVICE rather than the startup '
            'gate — so a direct caller meets it too, which is how the sweep '
            'is reached outside a start',
        clauses: ['refuses the unanchored-enrollment sweep']);
    provenIn('packages/at_client/test/enrollment_conveyance_guard_test.dart',
        'but still approves a request that carries its own wrapped key',
        proves: 'the control, and the reason the guard keys on the missing '
            'wrapped key rather than on the advertised package: a package '
            'rides every mode, so keying on it would refuse legacy enrolments '
            'that need none of this',
        clauses: ['carries its own wrapped key']);
    provenIn('packages/at_client/test/enrollment_conveyance_guard_test.dart',
        'and a PQ-capable posture is refused neither',
        proves: 'the second control: the refusals are about the posture, not '
            'about the fixture');
  });

  test('UC-G3.11 · a pre-enrollment atSign gives itself a first enrollment',
      () {
    provenIn(
        'tests/at_onboarding_cli_functional_tests/test/pq_pre_enrollment_retrofit_test.dart',
        'a pre-enrollment atSign at a post-quantum posture gives itself its '
            'first enrollment',
        proves: 'the whole row against a real atServer, and it reads the '
            'ROSTER rather than the client: an enroll:request on a legacy '
            'connection is a retrofit of primary, which the atServer approves '
            'outright and records as the successor\'s predecessor. It also '
            'establishes the precondition — the virtualenv pre-provisions demo '
            'atSigns, so what this atSign\'s roster already holds is measured '
            'rather than assumed',
        clauses: [
          'asks the atServer for a first enrollment',
          'the grants are',
          'its own retrofit, so sibling clones',
        ]);
    provenIn(
        'tests/at_onboarding_cli_functional_tests/test/pq_pre_enrollment_retrofit_test.dart',
        'the same atSign shape at a legacy posture does not',
        proves: 'the control, live, on the same fixture with only the posture '
            'differing — and it can go red while every assertion above stays '
            'green, which is what makes it a control rather than a restatement',
        clauses: ['asks for nothing and leaves nothing behind']);
    provenIn('packages/at_client/test/first_enrollment_identity_test.dart',
        'the device name is NOT the bare constant',
        proves: 'the device-name rule at the unit level, where the live arm '
            'can only observe one device. A shared constant would let the '
            'FIRST clone of a copied keyfile upgrade and leave every other '
            'refused at every start, for ever, with nothing on the device '
            'saying why — and one live atSign cannot see that',
        clauses: ['fresh UUID per call']);
    provenIn('packages/at_client/test/first_enrollment_identity_test.dart',
        'two clients of one keyfile ask for different device names',
        proves: 'the same rule stated as the property that matters, rather '
            'than as the absence of a constant');
    provenIn('packages/at_client/test/pre_enrollment_retrofit_drive_test.dart',
        'a client holding no enrollment asks the atServer for one',
        proves: 'the drive itself in-process — that the START is what asks, '
            'rather than a caller having to. The live arm proves the outcome; '
            'this proves which code path produced it');
  });

  test(
      'UC-G3.12 · a link vouches for one key, so a change to another key '
      'leaves it standing', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test('UC-G3.13 · the kind of a link follows from its signer', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.14 · enroll:link admits only the target or a caller that '
      'could approve it', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test('UC-G3.15 · enroll:link checks structure, and writes all or nothing',
      () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test('UC-G3.16 · a link replaces only the link its writer found', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test('UC-G3.17 · any other write of B\'s _apsk keeps B\'s links', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.18 · an enrollment links a key it adds, using one it has '
      'already linked, before signing with it', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.19 · a chain link is signed only by a key that has a link, '
      'and a root link only by the root', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.20 · content is signed with the keys that have links, while '
      'there are any', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.21 · an enrollment\'s authentication key takes no links, and '
      'gives none', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.22 · a fully privileged enrollment mints a missing signing '
      'root when it starts, and anchors the atSign', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.23 · a root holder\'s sweep gives every key without a sound '
      'root link one', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test('UC-G3.24 · the walk follows keys, and stops at a cycle', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.25 · the approver\'s view shows whether each enrollment is '
      'anchored', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.26 · links never travel by envelope, and the old link fields '
      'are gone', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.27 · on an atServer without enroll:link, nothing is linked '
      'and everything else works', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.28 · a bare RSA client data signing key is linked like a listed '
      'one', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.29 · an enroll:update cannot make B\'s client data signing key '
      'its authentication key', () {
    fail('not implemented');
  }, skip: perKeyLinks);

  test(
      'UC-G3.30 · a link vouches for the key it names, not for every key '
      'under its kid', () {
    fail('not implemented');
  }, skip: perKeyLinks);
}
