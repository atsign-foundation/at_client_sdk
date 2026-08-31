/// A5 · Rotation & revocation (new world).
///
/// The two levers are distinct and must not be conflated: CK rotation is the
/// cheap O(1) coarse-FS lever; nskey-KEYPAIR rotation is the heavy
/// O(n)-per-enrollment revocation + post-compromise-security lever.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 6.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('A5 · rotation & revocation', () {
    test('UC-A5.1(a) · coarse forward secrecy by rotating the symmetric CK',
        () {
      // GIVEN the app_1.my_apps@alice nskey exists.
      // WHEN  alice1 cuts a new CK, conveys it once sealed to the nskey, points
      //       new writes at it, then DELETES the old CK's at/nskey conveyance
      //       record and every enrollment evicts the cached old CK.
      // THEN  old-CK-era data becomes undecryptable — the nskey private cannot
      //       help, since no sealed copy of the old CK survives. Retaining the
      //       old conveyance instead = history access (the per-namespace FS
      //       retention knob).
      provenIn(
          'tests/at_functional_test/test/content_key_rotation_live_test.dart',
          'deleting the superseded conveyance makes its era undecryptable',
          proves: 'a value written under the first CK reads back (the control '
              'arm), the rotation deletes its conveyance from the atServer, and '
              'the same read then fails with the nskey private untouched — '
              'while a value written under the successor round-trips. The '
              'sibling test in that file holds the retention knob\'s other '
              'position: rotating WITHOUT the delete leaves the era readable, '
              'which is the default.',
          clauses: [
            'old-CK-era data becomes undecryptable (the nskey private cannot '
                'help',
          ]);
    });

    test('UC-A5.1(b) · revocation + PCS by rotating the nskey keypair', () {
      // GIVEN the nskey exists and an enrollment must be excluded.
      // WHEN  alice1 takes the _nskeylock lock, mints the next nskey keypair
      //       EXCLUDING the revoked enrollment, OVERWRITES
      //       public:__nskey.<ns>@alice with the new {nskeyKid, publicKey}, and
      //       pushes the successor private to surviving enrollments via __ssenv.
      // THEN  new CKs seal to the successor nskey and their conveyances carry
      //       the new nskeyKid; survivors retain the prior private so retained
      //       history still opens. A peer notices only at its next
      //       ensureCurrent re-plookup — WITHOUT that the revocation does not
      //       hold, since a peer still sealing to the superseded generation
      //       hands the revoked enrollment a key it can open. A joiner approved
      //       after the rotation is pushed EVERY generation its approver holds
      //       for the namespaces it was approved for, with requestSecret as
      //       the backstop for one the push missed. Heavy,
      //       O(n)-per-enrollment, DISTINCT from CK rotation.
      provenIn(
        'tests/at_functional_test/test/nskey_rotation_live_test.dart',
        'UC-A5.1(b) · a rotation publishes a successor',
        proves: 'three live enrollments: the rotation overwrites the published '
            'advertisement (read back by an enrollment that did NOT rotate, so '
            'it is the atServer\'s copy and not the rotator\'s memory), pushes '
            'the successor private to the survivor\'s keyfile, drops the '
            'excluded enrollment from the roster the push enumerates (with the '
            'unexcluded control arm), and retains the superseded private so '
            'records sealed to it still open. It then writes on the nskey data '
            'path either side of the rotation and reads which generation each '
            'content key\'s conveyance was sealed to: the first names the '
            'generation published at the time, the second names the successor, '
            'and they differ. Same client, same ring, same namespace — the '
            'rotation is the only thing that changed between the two writes, '
            'which is what tells a writer that MOVED from one that was always '
            'going to name that kid. Without it a rotation whose successor no '
            'writer used would satisfy every assertion above while leaving '
            'every new record sealed to the generation the excluded enrollment '
            'still holds.',
        clauses: [
          'new CKs are sealed to the successor nskey',
        ],
      );
      provenIn(
        'packages/at_client/test/ck_manager_test.dart',
        'cuts a fresh CK when the destination has rotated its nskey',
        proves: 'the peer half of the same clause, which the live arm above '
            'does not reach: a sender that has already conveyed a CK to one '
            'generation re-checks on its next ensureCurrent, sees the '
            'advertised kid has changed, and cuts a fresh CK to the successor '
            'rather than going on sealing to the superseded one — asserted as '
            'a COUNT of conveyances written, so a re-seal shows up as a second '
            'entry instead of being invisible. In-process because there is no '
            'atServer in the decision: the input is an advertisement and the '
            'output is whether a fresh key was cut.',
        clauses: [
          'new CKs are sealed to the successor nskey',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_self_heal_test.dart',
        'is pushed EVERY generation its approver holds, not just the live one',
        proves: 'the late-joiner clause, which said "the current generation '
            'only" until 2026-08-27 and which the approval path has never '
            'done. `conveyHeldPrivatesTo` reads every held generation for the '
            'approved namespaces and conveys each under its own nskeyKid, '
            'which is what a retained conveyance names — so retained history '
            'opens without a pull round trip. Two DISTINCT generations are '
            'asserted distinct first, or "both were sent" is satisfied by '
            'one. Its pair, "a namespace the joiner was not approved for is '
            'not conveyed", is what keeps "every" bounded by the approval '
            'rather than by what the keyfile happens to hold. Mutation-proven '
            'twice: conveying only the first generation reddens the count, '
            'and dropping the approval filter reddens the pair',
        clauses: ['pushed **every generation its approver holds**'],
      );

      // The sender-side half — a peer re-plookups and cuts a fresh CK when the
      // advertised nskeyKid changes — is `ensureCurrent`'s rotation check,
      // covered by ck_manager_test.dart's generation tests and exercised live
      // by nskey_cross_atsign_test.dart's rotation case.
    });

    test('UC-A5.2 · per-enrollment auth revocation', () {
      provenIn(
          'packages/at_client/test/pairwise_secret_sharing_test.dart',
          'a surviving child of a revoked parent is still answered, by the '
              'holder that just refused the parent',
          proves: 'the hazard the clause names, as a differential in ONE '
              'holder pass: one revoke removes exactly that id from the '
              'roster, the revoked requester is refused, and the enrollment it '
              'self-spawned is served the successor private - roster '
              'membership is the whole gate, and the serve path has no notion '
              'of an ancestor',
          clauses: ['is answered when it asks a holder']);
      // GIVEN @alice pq-native; the keyfile holding E2's APKAM keypair is lost.
      // WHEN  the operator runs enroll:revoke on E2.
      // THEN  E2's one APKAM keypair can no longer authenticate; alice1 is
      //       unaffected; E2 gets no new secrets — excluded at BOTH
      //       discovery+push and the requestSecret pull serve.
      provenIn('tests/at_functional_test/test/nskey_rotation_live_test.dart',
          'UC-A5.2/A5.3 · a revoked enrollment cannot authenticate',
          proves:
              'the revoked enrollment\'s own APKAM keypair authenticates on '
              'a fresh connection before the revoke and is refused after it, '
              'while a sibling enrollment still authenticates; and it disappears '
              'from the enroll:listns roster that both the push and the serve '
              'enumerate. The pull-serve half of "excluded at both" is pinned '
              'deterministically at unit level by the revocation-guard group in '
              'test/pairwise_secret_sharing_test.dart, where a holder refuses a '
              'requester the roster no longer lists and serves the same request '
              'while it is still listed.',
          clauses: [
            'E2\'s one APKAM keypair can no longer authenticate',
          ]);
    });

    test('UC-A5.3 · enrollment revocation composes with keypair rotation', () {
      // GIVEN enrollment E2 compromised (it holds exactly one APKAM keypair),
      //       and E2 has self-enrolled at least one successor.
      // WHEN  an enrollment holding rw on __manage calls
      //       revokeEnrollmentAndRotate(E2).
      // THEN  E2's APKAM keypair is cut at auth, paired with nskey-keypair
      //       rotation (UC-A5.1b) to deny new-data keys. Only that first arm is
      //       pinned here.
      //
      // ⛔ The row's second clause - that revoking E2 revokes E2's whole
      //    subtree, so the subtree leaves every roster and the client's
      //    exclusion set stays the ONE id named - is RULED AND NOT YET BUILT,
      //    and is unprovable from this repo at all: it is closed by an
      //    at_server test asserting a descendant is revoked and absent from
      //    enroll:listns. The cited test below exercises no self-enrolment.
      //
      // ⚠️ This comment required the EXCLUSION SET to be the whole subtree,
      //    walked client-side, until 2026-08-31. That was the wrong layer: an
      //    exclusion set binds only the client that computes it, while approval
      //    state is consulted by every roster query on every client.
      provenIn('tests/at_functional_test/test/nskey_rotation_live_test.dart',
          'UC-A5.3 · revokeEnrollmentAndRotate revokes first',
          proves: 'the composition run against a live atServer by a privileged '
              'operator enrollment: revoke, then rotate every namespace the '
              'target could read, excluding it. The successor is published, the '
              'revoked enrollment does not hold it even after the sweep that '
              'would have carried a pull\'s answer, and the owner retains the '
              'superseded private. The revoke-before-rotate ORDER — which is '
              'what makes the exclusion enforceable rather than advisory — is '
              'asserted directly in test/nskey_rotation_test.dart.',
          clauses: [
            'E2\'s APKAM keypair is cut at auth',
          ]);
    });

    test(
        'UC-A5.4 \u00b7 the content-key lever is a policy the application '
        'supplies', () {
      // GIVEN an application that supplied a CkRotationPolicy.
      // THEN  asked before the current key is returned, and only once one
      //       exists; handed destination/namespace/ckKid/cutAt/now; a restart
      //       takes the age from the record; a yes cuts, conveys and RETAINS
      //       the superseded conveyance; the default is seven days inclusive.
      provenIn('packages/at_client/test/ck_manager_test.dart',
          'a policy that says yes cuts a fresh content key',
          proves: 'the ask itself and what it is handed in one test: it '
              'collects every CkRotationContext the manager builds, so the '
              'destination, the namespace and the ckKid are read off the real '
              'context rather than off a fixture',
          clauses: [
            'asked **before the already-current key is returned**',
            'carrying the **destination** as well as the namespace',
          ]);
      provenIn('packages/at_client/test/ck_manager_test.dart',
          'the default policy leaves a fresh content key alone',
          proves: 'the control on the same fixture and the same two writes: '
              'without it, "a yes cuts a fresh key" is satisfied by a manager '
              'that cuts one on every write regardless of the answer');
      provenIn('packages/at_client/test/ck_manager_test.dart',
          'a resumed content key takes its age from the record, not this clock',
          proves: 'the restart clause, and the fixture is built for exactly '
              'this: the conveyance createdAt is a fixed unmistakable date, so '
              'an assertion that matched `now` would pass whether the age came '
              'from the record or from the device clock',
          clauses: ['takes its **age from that record\'s own date**']);
      provenIn('packages/at_client/test/ck_manager_test.dart',
          'cuts a successor and leaves the superseded conveyance in place',
          proves: 'RETENTION, which is the half a reader is most likely to '
              'get backwards — the superseded conveyance record survives the '
              'rotation, and that is what lets a later joiner read what was '
              'written before it. Deleting it is UC-A5.1(a), a separate and '
              'deliberate act',
          clauses: ['the superseded conveyance record is **retained**']);
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'the period is SEVEN days, pinned as a literal',
          proves: 'the default period as a raw-literal pin rather than a '
              'round trip through the constant that defines it, so an '
              'intended change edits the pin and that edit is the review',
          clauses: ['`rotateCkAfterOneWeek`']);
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'a key a week old or older is replaced',
          proves: 'the boundary is INCLUSIVE, which is the arm an off-by-one '
              'would silently move');
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'a key younger than a week is left alone',
          proves: 'the other side of the boundary');
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'age is measured against the now it is given, not the clock',
          proves: 'that `now` is a parameter rather than a read, which is what '
              'makes an application\'s policy testable without a clock');
    });

    test(
        'UC-A5.5 \u00b7 the namespace-key lever fires on a cause, and is asked '
        'at exactly two points', () {
      provenIn('packages/at_client/test/nskey_seeding_test.dart',
          'a sibling publishing mid-route does not become a rotation',
          proves: 'the third ask is closed, measured rather than reasoned: a '
              'ring answering null then an advertisement across the route '
              'records TWO reads and ZERO asks. Before the fix it recorded '
              'one ask, so the arm discriminates rather than restating',
          clauses: ['askRotationPolicy: false']);
      // GIVEN an application that supplied an NskeyRotationPolicy.
      // THEN  asked before a CK is conveyed but only for this atSign's own
      //       namespace key; asked once per authorised namespace at start;
      //       there is no third ask; handed the advertisement's own dates; a
      //       yes mints, retains and conveys; the default is never.
      provenIn('packages/at_client/test/ck_manager_test.dart',
          'the namespace-key hook is asked only where this atSign owns the key',
          proves: 'the first ask AND the constraint that makes it safe: a '
              'sender cannot replace a peer\'s namespace key, so the hook is '
              'consulted for the client\'s own atSign and not for a peer '
              'destination. Both arms are in the one test',
          clauses: [
            '**only where the destination is this client\'s own atSign**'
          ]);
      provenIn('packages/at_client/test/nskey_seeding_test.dart',
          'a published generation is put to the policy, with its own dates',
          proves: 'the second ask and what it is handed. It asserts the '
              'createdAt is the ADVERTISEMENT\'s minted-at rather than this '
              'device\'s clock, which is what lets every enrollment of one '
              'atSign reach the same answer from the same record',
          clauses: [
            'once per authorised namespace at every client start',
            'the `createdAt` **the advertisement itself states**',
          ]);
      provenIn('packages/at_client/test/nskey_rotation_test.dart',
          'publishes a fresh generation and keeps the superseded private',
          proves: 'the mint and the RETENTION halves of what a yes does — the '
              'superseded private survives, which is what keeps records '
              'sealed to it readable',
          clauses: ['fresh material is minted, the previous private is']);
      provenIn('packages/at_client/test/nskey_rotation_test.dart',
          'pushes the successor private to the namespace members',
          proves: 'the conveyance half, which is what makes the rotation O(n) '
              'per enrollment and therefore the expensive lever');
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'never, at any age',
          proves: 'the default, at an age no schedule would leave alone — so '
              'it is the POLICY being asserted and not a period',
          clauses: ['`neverRotateNskey`']);
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'it is a policy rather than an absent one',
          proves: 'that the default is a closure that says no rather than a '
              'null, which is what lets every call site ask unconditionally');

      // ⛔ "There is no third ask" is deliberately UNPINNED. It is an absence
      // — that `AtClient.ensureReachable` cannot reach the policy, because it
      // returns alreadyReachable in exactly the branch where a generation is
      // published and that is the only branch `seedNamespace` consults the
      // policy in. Read at both ends on 2026-08-31 and true, but no test
      // asserts it and one would have to drive a whole AtClientImpl to try.
    });

    test(
        'UC-A5.6 \u00b7 where a lever is not asked, and where a yes is refused '
        'out loud', () {
      // THEN  nothing published is a cold start and the policy is not asked;
      //       the start-of-client ask follows the posture; a yes with nowhere
      //       to convey is refused LOUDLY, the ask coming first deliberately;
      //       a policy that throws rotates nothing.
      provenIn('packages/at_client/test/nskey_seeding_test.dart',
          'nothing published is a cold start, and the policy is not asked',
          proves: 'the skip, asserted on the RECORDED ASKS rather than on the '
              'return value: the fixture answers yes, so a false return alone '
              'would not distinguish "not asked" from "asked and overridden"',
          clauses: ['not asked when no generation is advertised']);
      provenIn('packages/at_client/test/nskey_seeding_test.dart',
          'seeding follows the posture, and the shipped default now seeds',
          proves: 'that the start-of-client ask is gated on the posture\'s '
              'seedNamespaceKeys, so it never runs at PqPosture.legacy',
          clauses: ['`AtClientPreference.seedNamespaceKeys` is true']);
      provenIn('packages/at_client/test/nskey_seeding_test.dart',
          'a yes with no substrate to convey over rotates nothing',
          proves: 'the refusal AND that the question was put first — it '
              'asserts the policy was consulted as its control, so the '
              'declined rotation is attributable to the missing substrate '
              'rather than to a question never asked. That ordering is the '
              'clause: checking first would be cheaper and would make an '
              'application\'s yes vanish without trace',
          clauses: ['the policy is consulted **before** the substrate check']);
      provenIn('packages/at_client/test/nskey_seeding_test.dart',
          'a policy that throws rotates nothing, and does not fail the caller',
          proves: 'that an application\'s bug in its own closure does not '
              'propagate into whatever write asked. Written 2026-08-31 with '
              'this clause: nothing covered it, and the control asserts the '
              'policy really was consulted so the false return is the catch '
              'rather than a question never put',
          clauses: ['the exception is caught, logged at warning']);
    });
  });
}
