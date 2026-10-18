import 'package:test/test.dart';

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
    provenIn(
        'packages/at_client/test/approve_link_flavour_test.dart',
        'when it approves B, then it calls enroll:link once for B with a root '
            'link for each key, each expecting none, and B reads anchored',
        proves: 'the call itself: one enroll:link naming B, carrying a link '
            'for each of its two listed keys, each sent expecting no link, '
            'and the walk then reading anchored. The kids the call carries are '
            'compared with the record\'s own, so a call linking one key of two '
            'goes red',
        clauses: [
          'it calls `enroll:link` once for B',
          'the links are root links',
          'B\'s record holds one link per `kid`',
        ]);
    provenIn(
        'packages/at_client/test/approve_link_flavour_test.dart',
        'when it approves B, then the links are chain links signed with that '
            'key',
        proves: 'the other flavour: an approver without the root signs each '
            'link with its own linked key, one signature each, whether or not '
            'it is fully privileged, and B still reads anchored',
        clauses: ['the links are root links']);
    provenIn(
        'packages/at_client/test/approve_link_flavour_test.dart',
        'when it approves B, then it sends no enroll:link, and the symmetric '
            'key still arrives',
        proves: 'the approver with neither: no call, and the symmetric key the '
            'enrollee is blocked polling for still reaches it',
        clauses: ['an approver with neither sends no']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.5 · an approver holding the root links the key of the '
            'enrollment it approves with a root link, and it reads anchored',
        proves: 'the root flavour against a real atServer: the link is on the '
            'stored record after the approval, and the walk reads anchored in '
            'one hop',
        clauses: [
          'the links are root links',
          'B\'s record holds one link per `kid`',
        ]);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.5 · an approver whose own key walks to the root links with a '
            'chain link signed with that key',
        proves: 'the chain flavour live: the stored link names the approving '
            'enrollment as its signer, and the walk goes through it',
        clauses: ['the links are root links']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.21 · an authentication key takes no link, and an approver with '
            'no linked key writes none',
        proves: 'the approver with neither, live: the enrollment it approves '
            'is approved and carries no link',
        clauses: ['an approver with neither sends no']);
  });

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
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when B lists a new key K3, then K1 keeps its link and still walks to '
            'the root',
        proves: 'a second key listed beside K1 leaves K1\'s link on the '
            'record, and the walk from K1 still reads anchored',
        clauses: ['K1\'s link is still on the record']);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when B retires K2, still listing it, then K2 keeps its link',
        proves: 'a retired key still listed keeps its link and still walks to '
            'the root, so what it signed still verifies',
        clauses: ['a retired K2, still advertised, keeps its link']);
    provenIn('tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.17 · other writes of an _apsk keep its links',
        proves: 'the first clause against a real atServer: an enroll:update '
            'that lists a second key leaves the first key\'s link as it was, '
            'and the walk from that key still reads anchored',
        clauses: ['K1\'s link is still on the record']);
  });

  test('UC-G3.13 · the kind of a link follows from its signer', () {
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when the walk runs, then the link is checked against that root key '
            'and reads anchored',
        proves: 'a link whose signer kid is a root key is a root link, checked '
            'against that key, and reads anchored in one hop',
        clauses: ['the first is checked against that root key only']);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when it was signed without the domain tag, then it reads broken',
        proves: 'the `at-root-link:` prefix is part of what a root link signs: '
            'a signature over the bare payload fails');
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when the record lists that root as retired, then it still reads '
            'anchored',
        proves: 'a retired root key still anchors, as the Given says');
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when the walk runs, then it continues from that key and reads '
            'anchored through it',
        proves: 'a link signed by another enrollment\'s key is checked against '
            'that key\'s entry, and the walk continues from it',
        clauses: ['the first is checked against that root key only']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when its signature fails, then it reads broken and is never tried as '
            'a chain link',
        proves: 'a link naming a root kid that fails is broken, with the root '
            'check\'s own reason, rather than being tried as a chain link',
        clauses: ['is never tried as a chain link']);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when the link names no signer kid, then it reads broken',
        proves: 'the second half of the second clause',
        clauses: ['is never tried as a chain link']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.5 · an approver whose own key walks to the root links with a '
            'chain link signed with that key',
        proves: 'both kinds against a real atServer: the approver\'s own root '
            'link anchors it, and the walk from the enrollment it approved '
            'goes through the approver\'s key to it',
        clauses: ['the first is checked against that root key only']);
  });

  test(
      'UC-G3.14 · enroll:link admits only the target or a caller that '
      'could approve it', () {
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.14 · enroll:link admits only the target or a caller that could '
            'approve it',
        proves: 'the refusals against a real atServer, each by its own reason: '
            'a caller without __manage, and one with __manage but not every '
            'namespace the target holds. Nothing is written, and the target '
            'linking its own key with the same link is admitted',
        clauses: ['the atServer refuses it, and nothing is written']);
    // NOTE: c2 also admits a CRAM connection, which only at_server's own suite
    // drives; nothing here opens one to call enroll:link, so c2 is not pinned.
  });

  test('UC-G3.15 · enroll:link checks structure, and writes all or nothing',
      () {
    provenIn('tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.15 · enroll:link checks structure, and writes all or nothing',
        proves: 'a call carrying a good link beside one for an unlisted kid is '
            'refused naming that kid, and the good link is not written either; '
            'a link naming another enrollment, and one over 16 KiB, are each '
            'refused; a call for a pending enrollment is refused; and one call '
            'carrying good links for two keys writes both',
        clauses: [
          'the whole call is refused, naming what failed',
          'a call for an enrollment that isn\'t approved is refused',
          'a call carrying well-formed links for K1 and K2 writes both',
        ]);
  });

  test('UC-G3.16 · a link replaces only the link its writer found', () {
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.16 · a link replaces only the link its writer found, compared '
            'as JSON',
        proves: 'against a real atServer: a write expecting no link where L1 '
            'stands is refused and L1 stays, and the same write expecting L1 '
            'replaces it',
        clauses: [
          'the atServer refuses the call, and L1 stays on K1',
          'when the copy it sends is L1',
        ]);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when another voucher wrote a chain link first and this one holds the '
            'root, then it reads again and replaces it, naming that link',
        proves: 'the losing voucher\'s retry when its link is a root link and '
            'it finds a chain link: a second call, expecting the chain link it '
            'read',
        clauses: ['when two vouchers each find no link on K1']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when another voucher wrote a sound link first and this one signs '
            'chain links, then it keeps the link it finds',
        proves: 'the other arm of the retry: a chain voucher that loses the '
            'race keeps the link it now finds and sends nothing more',
        clauses: ['when two vouchers each find no link on K1']);
  });

  test('UC-G3.17 · any other write of B\'s _apsk keeps B\'s links', () {
    provenIn('tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.17 · other writes of an _apsk keep its links',
        proves: 'against a real atServer: an enroll:update republish that adds '
            'a key, and a put carrying the old version 1 link fields, each '
            'leave the link as it was; an enroll:update that stops listing the '
            'key removes its link in the same write',
        clauses: [
          'the links for K1 and K2 are still on the record afterwards',
          'when the new value no longer lists K2 at all',
        ]);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when B republishes its _apsk, then the put carries no appMetadata',
        proves: 'the client half: a republish sends no link fields of its own, '
            'so nothing but the atServer\'s carry-over keeps the links');
    // NOTE: c3, the atServer serialising an enroll:link with a republish, is
    // pinned only in at_server's own suite.
  });

  test(
      'UC-G3.18 · an enrollment links a key it adds, using one it has '
      'already linked, before signing with it', () {
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when B advertises K2, then B links K2 itself through enroll:link on '
            'its own record, signed with K1',
        proves: 'the reconcile that mints K2 calls enroll:link on B\'s own '
            'record with one link, for K2, signed with K1 and naming B; the '
            'walk from K2 goes through K1 to the root; and K1, retired in the '
            'same reconcile, keeps its own link',
        clauses: [
          'B writes K2\'s link itself',
          'when B later retires K1, K1\'s link stays',
        ]);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when it signs content, then only the keys with a link sign',
        proves: 'with K1 linked and K2 not, content carries K1\'s signature '
            'alone',
        clauses: ['until K2\'s link is on the record']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.18 · an enrollment links a key it adds, using one it has '
            'already linked',
        proves: 'against a real atServer: an enrollment whose start minted an '
            'ML-DSA-65 key beside its linked RSA one has that key\'s link on '
            'its record, signed by its own RSA key, and the walk from it reads '
            'anchored',
        clauses: ['B writes K2\'s link itself']);
  });

  test(
      'UC-G3.19 · a chain link is signed only by a key that has a link, '
      'and a root link only by the root', () {
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when it holds neither the root nor a key with a link, then it has no '
            'voucher, and its authentication key never is one',
        proves: 'an enrollment with neither has nothing to vouch with, whether '
            'its _apsk is its authentication key or an unlinked client data '
            'signing key',
        clauses: ['A writes no link for B']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when its own linked key no longer walks to the root, then it has no '
            'voucher',
        proves: 'a key with a link vouches only while its own walk reads '
            'anchored, so a chain link is signed only by a key that walks to '
            'the root when it signs',
        clauses: ['every chain link on any record was signed by a key']);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when it is not fully privileged, then it signs no root link with it',
        proves: 'the root half: holding the root private is not enough to sign '
            'a root link without full privilege',
        clauses: ['every chain link on any record was signed by a key']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.21 · an authentication key takes no link, and an approver with '
            'no linked key writes none',
        proves: 'the first clause live: an approver whose _apsk is its '
            'authentication key approves an enrollment and writes no link for '
            'it',
        clauses: ['A writes no link for B']);
  });

  test(
      'UC-G3.20 · content is signed with the keys that have links, while '
      'there are any', () {
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when it signs content, then only the keys with a link sign, and with '
            'none linked every key signs',
        proves: 'all three states in one enrollment: no key linked signs with '
            'both, K1 linked signs with K1 alone, both linked signs with both',
        clauses: [
          'the content carries one signature, made with K1',
          'an enrollment with no key that has a link signs with every key',
        ]);
    // NOTE: c3, the key package signed at enroll:request, has no citation of
    // its own: no test signs one with a link standing.
  });

  test(
      'UC-G3.21 · an enrollment\'s authentication key takes no links, and '
      'gives none', () {
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when the target lists its authentication key, then that key takes no '
            'link',
        proves: 'a voucher holding the root sends nothing for an _apsk that is '
            'its enrollment\'s authentication key, and the walk reads unsigned',
        clauses: ['no link is written for that key']);
    provenIn(
        'packages/at_client/test/approve_link_flavour_test.dart',
        'when B\'s _apsk is its authentication key, then it sends no '
            'enroll:link and B reads unsigned',
        proves: 'the same at approval, keyed on the enrollment record\'s '
            'apkamPublicKey');
    provenIn('packages/at_client/test/chain_sweep_test.dart',
        'an enrollment whose _apsk is its authentication key is left alone',
        proves: 'the same in a root holder\'s sweep');
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.21 · an authentication key takes no link, and an approver with '
            'no linked key writes none',
        proves: 'against a real atServer: the approval writes no link for an '
            'authentication key, the atServer refuses one asked for by a root '
            'holder, the walk reads unsigned, and the enrollment, approving '
            'another, signs no link for it',
        clauses: ['no link is written for that key']);
    // NOTE: c2, the key B mints later being linked, has no citation of its
    // own: no test mints a client data signing key for such an enrollment and
    // then links it.
  });

  test(
      'UC-G3.22 · a fully privileged enrollment mints a missing signing '
      'root when it starts, and anchors the atSign', () {
    provenIn(
        'packages/at_client/test/startup_call_order_test.dart',
        'a fully privileged enrollment whose atSign publishes no root mints '
            'one at start, then root-links its own key',
        proves: 'the start itself: the root is written, then enroll:link '
            'root-links the enrollment\'s own key, in that order',
        clauses: ['F mints the signing root, root-links its own keys']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when the atSign publishes no root and it is fully privileged, then '
            'minting one root-links its own keys through enroll:link',
        proves: 'minting is what root-links the minter\'s own keys, through '
            'one enroll:link on its own record, and the walk then reads '
            'anchored');
    provenIn(
        'packages/at_client/test/chain_sweep_test.dart',
        'when the sweep runs, then the key gets a root link stating it found '
            'none',
        proves: 'the rest of the first clause: a root holder root-links a key '
            'on another enrollment that has no link',
        clauses: ['F mints the signing root, root-links its own keys']);
    provenIn('packages/at_client/test/pq_signing_root_test.dart',
        'losing the mint lock generates nothing and files nothing',
        proves: 'of two fully privileged enrollments minting together, the one '
            'that loses the mint lock publishes nothing',
        clauses: ['only one root is published']);
    provenIn('packages/at_client/test/pq_signing_root_test.dart',
        'a restricted enrollment mints nothing',
        proves: 'an enrollment that is not fully privileged mints no root',
        clauses: ['an enrollment that isn\'t fully privileged mints nothing']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.22 · a fully privileged enrollment mints a missing signing root '
            'when it starts, and root-links its own keys',
        proves: 'against a real atServer, on an atSign that published no root '
            'before: the enrollment\'s start publishes one, files its private, '
            'and root-links its own keys, and its walk reads anchored',
        clauses: ['F mints the signing root, root-links its own keys']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.23 · a root holder\'s sweep replaces a chain link with a root '
            'link',
        proves: 'the sweep half of the first clause live: the root holder '
            'root-links a key on another enrollment',
        clauses: ['F mints the signing root, root-links its own keys']);
    provenIn(
        'tests/at_functional_test/test/pq_signing_root_mint_lock_test.dart',
        'a second signing-root mint lock create is refused',
        proves: 'the atServer refuses a second create of the mint lock, which '
            'is what leaves one minter of two',
        clauses: ['only one root is published']);
  });

  test(
      'UC-G3.23 · a root holder\'s sweep gives every key without a sound '
      'root link one', () {
    provenIn(
        'packages/at_client/test/chain_sweep_test.dart',
        'when the sweep runs, then the key gets a root link stating it found '
            'none, and the next sweep links nothing',
        proves: 'a key with no link gets a root link whose call expects none, '
            'and a second sweep sends nothing for the root link it now finds',
        clauses: [
          'each of those keys gets a root link from F',
          'a key whose root link passes its check is left',
        ]);
    provenIn(
        'packages/at_client/test/chain_sweep_test.dart',
        'when the sweep runs, then a root link replaces it, the call naming '
            'the chain link it found',
        proves: 'a chain link is replaced, the call expecting the chain link',
        clauses: ['each of those keys gets a root link from F']);
    provenIn('packages/at_client/test/chain_sweep_test.dart',
        'when the sweep runs, then it is replaced',
        proves: 'a root link that fails its check is replaced',
        clauses: ['each of those keys gets a root link from F']);
    provenIn('packages/at_client/test/chain_sweep_test.dart',
        'a fully privileged sweeper without the root private links nothing',
        proves: 'the Given\'s holder is required: full privilege alone does '
            'not sweep');
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.23 · a root holder\'s sweep replaces a chain link with a root '
            'link',
        proves: 'against a real atServer: a chain-linked key walks to the root '
            'in one hop after the sweep',
        clauses: ['each of those keys gets a root link from F']);
  });

  test('UC-G3.24 · the walk follows keys, and stops at a cycle', () {
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when the walk runs from either, then it reads broken and stops',
        proves: 'two chain links naming each other read broken from either '
            'end, rather than walking for ever',
        clauses: ['it reads **broken**, and stops']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when a voucher would link a key its own chain passes through, then '
            'it links nothing',
        proves: 'the voucher refuses the write that would close a cycle',
        clauses: ['a voucher never links a key']);
  });

  test(
      'UC-G3.25 · the approver\'s view shows whether each enrollment is '
      'anchored', () {
    provenIn(
        'packages/at_onboarding_cli/test/auth_cli_list_test.dart',
        'at_activate list shows whether each approved enrollment is anchored, '
            'naming a key that fails',
        proves: 'the CLI view: an Anchored column reading anchored, unsigned, '
            'or the verdict and kid of a failing key, and nothing walked for a '
            'pending enrollment',
        clauses: ['a row shows **anchored** when every key']);
    provenIn(
        'packages/at_client_flutter/test/enrollment_request_list_test.dart',
        'the approved enrollments show whether their keys are anchored, naming '
            'a key that fails',
        proves: 'the same three labels in the Flutter approver view, below the '
            'pending requests',
        clauses: ['a row shows **anchored** when every key']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when every active key with a link walks to the root, then it reads '
            'anchored, though a newer key has no link yet',
        proves: 'the verdict both views show reads anchored while a new key '
            'waits for its link',
        clauses: ['the enrollment whose new key isn\'t linked yet']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when a linked key fails, then it reads that key\'s verdict, naming '
            'the key',
        proves:
            'the verdict the views label: the failing key\'s, with its kid');
  });

  test(
      'UC-G3.26 · links never travel by envelope, and the old link fields '
      'are gone', () {
    provenIn('packages/at_client/test/approve_link_flavour_test.dart',
        'when it approves B, then no link travels in an envelope',
        proves: 'an approval that links sends the link by enroll:link and '
            'conveys no link secret',
        clauses: ['every link is written through `enroll:link`']);
    provenIn('tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.26 · an approval conveys no link in an envelope',
        proves: 'the same against a real atServer: the enrollee sweeps what '
            'was conveyed, finds no link among it, and the link is on its '
            'record instead',
        clauses: ['every link is written through `enroll:link`']);
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when B republishes its _apsk, then the put carries no appMetadata',
        proves: 'a republish writes no link field at all');
    // NOTE: c2 is in part an absence — nothing reads the old fields — so it is
    // not pinned; the citation above establishes only the write half.
  });

  test(
      'UC-G3.27 · on an atServer without enroll:link, nothing is linked '
      'and everything else works', () {
    provenIn('packages/at_client/test/pq_signing_chain_test.dart',
        'when a voucher links a key and the atServer is ',
        proves: 'for both ways an older atServer refuses the verb, the voucher '
            'links nothing, does not throw, and the walk reads unsigned',
        clauses: ['no link is written, and every enrollment reads']);
    provenIn('packages/at_client/test/approve_link_flavour_test.dart',
        'when an approver holding the root approves B and the atServer is ',
        proves: 'the approval half of the second clause: the conveyance '
            'completes and the symmetric key arrives, for both refusals',
        clauses: ['no link is written, and every enrollment reads']);
    // NOTE: c2 also names the key addition, the start and content signing,
    // which no test drives against an atServer refusing enroll:link.
  });

  test(
      'UC-G3.28 · a bare RSA client data signing key is linked like a listed '
      'one', () {
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when a root holder links it and it then vouches for another '
            'enrollment, then both walk to the root',
        proves: 'a key published bare is linked under the kid derived from it, '
            'walks to the root, and signs a link for another enrollment that '
            'walks to the root through it',
        clauses: ['treat the bare value as one `rsa2048` entry']);
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when B advertises K2, then B links K2 itself through enroll:link on '
            'its own record, signed with K1',
        proves: 'the move to pqActive: B\'s single RSA key, published bare, is '
            'retired in the reconcile that mints its ML-DSA-65 key, keeps the '
            'kid the walk reaches it by, and keeps its link',
        clauses: ['the RSA key keeps the same `kid` and keeps its link']);
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.18 · an enrollment links a key it adds, using one it has '
            'already linked',
        proves: 'against a real atServer: the RSA key a pqReady enrollment '
            'enrolls with carries the approver\'s link, and the atServer '
            'accepts the enrollment\'s own link signed with it',
        clauses: ['treat the bare value as one `rsa2048` entry']);
  });

  test(
      'UC-G3.29 · an enroll:update cannot make B\'s client data signing key '
      'its authentication key', () {
    provenIn(
        'tests/at_functional_test/test/per_key_links_live_test.dart',
        'UC-G3.29 · an enroll:update cannot make a client data signing key the '
            'authentication key, and installs one listed alone with no link',
        proves: 'against a real atServer: the rotation onto a listed, linked '
            'key is refused naming its kid and leaves the record as it was; '
            'the rotation of an enrollment whose _apsk is its own key alone '
            'with no link is accepted',
        clauses: [
          'the atServer refuses the update, naming K1',
          'an update that leaves K1 as the only key',
        ]);
  });

  test(
      'UC-G3.30 · a link vouches for the key it names, not for every key '
      'under its kid', () {
    provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'when the walk runs from the entry a root link does not name, then it '
            'reads broken; from the entry it names, anchored',
        proves: 'two entries under one kid with different keys: the walk from '
            'the one the link does not name reads broken, naming why, and from '
            'the one it names reads anchored',
        clauses: [
          'since the link names another key',
          'reads **anchored** when that link is a root link',
        ]);
  });
}
