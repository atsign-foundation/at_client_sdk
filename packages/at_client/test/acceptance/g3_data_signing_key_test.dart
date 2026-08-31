import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part G3 — the data signing key an enrollment owns from birth
/// (`acceptance.md` section 18).
///
/// Section 16 is about what an `_apsk` record MEANS to a reader. This file is
/// about the key it names: which door minted it, what has to agree on how the
/// record spells it, and what breaks when the record moves under a signature
/// that vouched for it.
///
/// ⚠️ **Three rows here are narrower than the work item that asked for them**,
/// and each says so on the row rather than only here: the preference's floor
/// rule reads one axis and not "any axis" (UC-G3.9), the no-provider approval
/// guard keys on the missing wrapped key and not on "a pq request"
/// (UC-G3.10), and the mismatch cluster has four refusal messages plus one
/// silent comparison rather than three (UC-G3.4).
void main() {
  test(
      'UC-G3.1 · every creation door files the private half, not just the '
      'public one', () {
    // GIVEN a client creating an enrollment through any of the three doors
    //       that mint one.
    // WHEN  the atServer answers with an enrollment id.
    // THEN  the private half is filed as typed sign: material under that id.
    // AND   an enrolment carrying no advertisedSigningKey files nothing.
    // AND   what is filed is the enrollment's, not the atSign's.
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
    // GIVEN an enrollment created holding the keypair its posture's in-use
    //       set names.
    // WHEN  that client starts and reconcileSigningKeys runs.
    // THEN  it mints nothing, retires nothing and publishes nothing.
    // AND   the mint refuses a set naming more than one algorithm.
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
    // GIVEN two composers writing one record — at_auth at enrolment and
    //       at_client at every start.
    // WHEN  the advertised signing key is a single active rsa2048 key.
    // THEN  both spell it bare, and both spell anything else as the array.
    // AND   a second condition on either side is a defect.
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

    // The clause about a SECOND condition is a statement about what must not
    // exist, and no test can assert the absence of a future condition. What
    // the four citations above buy is that the two composers agree today, in
    // both directions, which is the whole of what is checkable.
  });

  test(
      'UC-G3.4 · a link is bound to the exact _apsk string, and a republish '
      'breaks it', () {
    // GIVEN a conveyed link whose payload carries the enrollee's entire
    //       published _apsk value.
    // WHEN  that value changes.
    // THEN  all five whole-string comparisons fail.
    // AND   the break is not self-healing: publish writes the value alone.
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'a conveyed CHAIN link is refused, naming the mismatch',
        proves: 'comparison 1 of 5, asserted on the REASON naming the '
            'mismatch rather than on a bare refusal — a link rejected for '
            'a bad signature would satisfy a throwsA and prove nothing about '
            'the binding',
        clauses: ['whole-string comparisons fails']);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'a conveyed ROOT link is refused, naming the mismatch',
        proves: 'comparison 2 of 5. The root path is separate code with its '
            'own fetch and its own message, so the chain arm above says '
            'nothing about it');
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'the walk reports a CHAIN link broken, not anchored',
        proves: 'comparison 3 of 5, and the verdict is the assertion: a walk '
            'that returned unsigned would also "not be anchored" while '
            'telling an operator the enrollment was never vouched for');
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'the walk reports a ROOT link broken, not anchored',
        proves: 'comparison 4 of 5');
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'an enrollment whose own key moved re-anchors itself',
        proves: 'comparison 5 of 5 — the one that refuses SILENTLY, returning '
            'a bool to its caller rather than a reason to an operator, and '
            'therefore the one no message-matching test could have found');
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'the child publishes the link onto its own key, value untouched',
        proves: 'that a link rides the record\'s appMetadata while the value '
            'stays as published — which is what makes a plain value-only '
            'write drop it',
        clauses: ['the break is not recoverable by the record alone']);
  });

  test(
      'UC-G3.5 · what an approver conveys is decided by possession as well as '
      'privilege', () {
    // THEN  privileged + root private     -> root link
    // AND   privileged + no root + a key  -> chain link
    // AND   privileged + neither          -> nothing, and the rest still flows
    // AND   not privileged                -> chain link
    provenIn('packages/at_client/test/approve_link_flavour_test.dart',
        'a fully privileged approver conveys a root link',
        proves: 'arm 1 — the posture-invariant anchor',
        clauses: ['conveys a **root** link, signed with the atSign']);
    provenIn(
        'packages/at_client/test/approve_link_flavour_test.dart',
        'a privileged approver with a data signing key but no root conveys a '
            'CHAIN link',
        proves: 'arm 2 — the arm that CHANGED on 2026-08-30. It conveyed '
            'nothing until then, on the reasoning that the every-start pull '
            'would heal possession and the sweep would anchor the enrollment '
            'later; the pull has one production caller and the sweep is a '
            'later startup step, so nothing re-attempted it',
        clauses: ['holds a data signing key of its own conveys']);
    provenIn(
        'packages/at_client/test/approve_link_flavour_test.dart',
        'a privileged approver holding NEITHER conveys no link, '
            'and everything else still flows',
        proves: 'arm 3, and the "everything else" is the point: the symmetric '
            'key still arrives. A guard that dropped the whole conveyance '
            'would cost the enrollee the one envelope it is blocked polling '
            'for',
        clauses: ['conveys **no link at all**']);
    provenIn('packages/at_client/test/approve_link_flavour_test.dart',
        'a non-privileged approver conveys the provisional chain link',
        proves: 'arm 4 — and it is the ordinary case rather than the edge, '
            'since approval takes __manage alone while full privilege takes '
            'w on both * and __manage',
        clauses: ['fully privileged conveys a chain link signed with its own']);
  });

  test(
      'UC-G3.6 · a legacy enrollment\'s authentication keypair signs data in '
      'memory only', () {
    // GIVEN an enrollment holding no typed sign: material.
    // WHEN  something asks what may sign.
    // THEN  the APKAM authentication keypair, built from atChops, never filed.
    // AND   once a signing key exists it stops signing AND stops being
    //       advertised in the same step — dropped, not retired.
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
    // GIVEN an enrollment holding no typed signing material whose APKAM
    //       authentication keypair is rsa2048.
    // WHEN  the in-use set names rsa2048.
    // THEN  it mints nothing.
    // AND   the exclusion is scoped to rsa2048 — an ML-DSA authenticator
    //       holding none still mints.
    // AND   pqActive and a retrofitted enrollment both still mint.
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
    // GIVEN a client whose startup has not reached its mint step.
    // WHEN  anything asks for the keys that may sign.
    // THEN  it answers from the keyfile immediately.
    // AND   it answers by READING, and returns the filed key once one is
    //       there.
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
    // THEN  an empty signing set beside a non-rsa2048 authentication key is
    //       refused, with legacy as the control.
    // AND   an explicit authenticationKeyAlgorithm weaker than the posture is
    //       refused.
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
    // GIVEN a client whose posture configures no post-quantum providers,
    //       meeting a pending enrolment with a key package and no wrapped key.
    // THEN  it throws BEFORE the approval reaches the atServer.
    // AND   it refuses the sweep too.
    // AND   the control: a request carrying its own wrapped key is approved.
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
    // GIVEN an atSign holding no enrollment, authenticating with the flat
    //       at_pkam_publickey.
    // WHEN  a client starts at a post-quantum posture.
    // THEN  it asks for a first enrollment and comes up on it.
    // AND   app constant + device constant + fresh UUID per call.
    // AND   grants are stated.
    // AND   control: the same shape at legacy asks for nothing.
    // AND   the flat root credential survives.
    provenIn(
        'tests/at_onboarding_cli_functional_tests/test/pq_pre_enrollment_retrofit_test.dart',
        'a pre-enrollment atSign at a post-quantum posture gives itself its '
            'first enrollment',
        proves: 'the whole row against a real atServer, and it reads the '
            'ROSTER rather than the client: the atServer parks such a request '
            'pending, so "approved" there means the client approved its own '
            'request over the same connection. It also establishes the '
            'precondition — the virtualenv pre-provisions demo atSigns, so '
            '"this atSign holds no enrollment" is measured rather than '
            'assumed',
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
}
