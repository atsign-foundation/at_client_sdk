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
      //       ensureCurrent re-plookup once its cached advertisement is
      //       advertisementTtl old — WITHOUT that re-fetch the revocation does
      //       not hold, since a peer still sealing to the superseded generation
      //       hands the revoked enrollment a key it can open. A re-fetch that
      //       cannot reach an answer keeps the cached generation for at most
      //       advertisementStaleGrace; a not-found drops it at once. A joiner
      //       approved after the rotation is pushed EVERY generation its
      //       approver holds in every namespace its grant covers, with
      //       requestSecret as the backstop for one the push missed. Heavy,
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
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'the advertisement is re-fetched once the TTL has passed',
        proves: 'the first leg of the bound: an advertisement cached past '
            'advertisementTtl is fetched again rather than served, counted as '
            'a second fetch against the first arm of the same group, which '
            'asserts one fetch inside the TTL.',
        clauses: [
          'cached advertisement is `advertisementTtl` (15 minutes) old',
        ],
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'a failed re-fetch stops serving the known key past the grace',
        proves: 'the second leg: a re-fetch that fails for any reason but a '
            'not-found serves the cached generation inside '
            'advertisementStaleGrace (the sibling tests, one of them with the '
            'AT0011 an unreachable peer atServer produces) and throws past it, '
            'rather than answering none, which the resolver would read as an '
            'empty level and walk past.',
        clauses: [
          'for at most `advertisementStaleGrace`',
        ],
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'a not-found on re-fetch ends sealing at once, inside the grace',
        proves: 'a not-found from the owner\'s atServer answers none with the '
            'grace fifteen minutes long, so the grace is not what ends it; its '
            'sibling shows the not-found also drops the cached generation, so '
            'a failed fetch afterwards throws instead of bringing it back.',
        clauses: [
          'answered not-found stops sealing to that peer at once',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_self_heal_test.dart',
        'is pushed EVERY generation its approver holds, not just the live one',
        proves: 'the late-joiner clause, which said "the current generation '
            'only" until 2026-08-27 and which the approval path has never '
            'done. `conveyHeldPrivatesTo` reads every held generation in the '
            'namespaces the grant covers and conveys each under its own nskeyKid, '
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
      provenIn(
        'packages/at_client/test/nskey_self_heal_test.dart',
        'a grant is conveyed the namespaces below it, read access included',
        proves: 'an approver holding sshnp, dev1.sshnp and notsshnp conveys '
            'the first two to a joiner granted sshnp:r, so a grant covers the '
            'namespaces below it and read access is enough; notsshnp is the '
            'control that the match is a dot-suffix. Its siblings show a * '
            'grant is conveyed every namespace held, and a grant that is only '
            'a prefix of a held namespace is conveyed nothing',
        clauses: ['in every namespace its grant covers'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_conveyance_reach_live_test.dart',
        'an approval conveys every key its approver holds that the new '
            'enrollment may read, all of them under *',
        proves: 'the same rule against a live atServer, where approval is the '
            'only route the keys have: an approver mints a namespace and one '
            'below it, then approves an enrollment granted only `*`, one '
            'granted read on the namespace above, and one granted another '
            'namespace. The first two are conveyed both keys and the third '
            'neither',
        clauses: ['in every namespace its grant covers'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_conveyance_reach_live_test.dart',
        'an approver that may only read a namespace it holds a key for still '
            'approves, and conveys the keys it may write',
        proves: 'an approver granted `r` on a namespace, holding its key from '
            'a mint, approves an enrollment granted only `*` against a live '
            'atServer: the approval completes, the key it may write is '
            'conveyed and the read-only one is not. With the secret-store '
            'route\'s skip and catch removed, the same test fails with the '
            'atServer\'s refusal of the envelope, thrown out of the approval',
        clauses: ['the approval still completes'],
      );
      provenIn(
        'packages/at_client/test/enrollment_conveyance_guard_test.dart',
        'is tried by neither route when its grants say so',
        proves: 'in an approval through the real conveyance, neither the '
            'keyfile route nor the secret-store route tries a write in a '
            'namespace the approver holds only `r` on, and the approval '
            'completes. Its sibling leaves the grants unknown, so the write '
            'is tried and refused, and the secrets after it still go. '
            'Mutation-proven: dropping either route\'s grants, or the '
            'per-secret catch, reddens them',
        clauses: ['the approval still completes'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_conveyance_reach_live_test.dart',
        'an approver conveys what the atServer lets it write in a dotted '
            'namespace, which its grant on the last segment decides',
        proves: 'against a live atServer, an approver granted `r` on a dotted '
            'namespace and `rw` on its last segment conveys that namespace\'s '
            'key to a `*` enrollment, and one granted the reverse does not, '
            'each narrower grant listed first. On the previous rule, which '
            'took the first grant listed, the first of those keys is skipped '
            'and the test fails',
        clauses: ['its approver may write'],
      );
      provenIn(
        'packages/at_client/test/authorised_namespaces_test.dart',
        'a grant on the last segment wins over a narrower one',
        proves: 'the approver resolves where it may write as the atServer '
            'does, by the grant on a namespace\'s last segment first, '
            'whatever order the grants are listed in',
        clauses: ['its approver may write'],
      );
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
      //       and E2 has approved at least one enrollment beneath it.
      // WHEN  an enrollment holding rw on __manage calls
      //       revokeEnrollmentAndRotate(E2).
      // THEN  E2's APKAM keypair is cut at auth, paired with nskey-keypair
      //       rotation (UC-A5.1b) to deny new-data keys. Only that first arm is
      //       pinned here.
      //
      // NOTE: the cascade is the atServer's, sentence by sentence, and its own
      //       suite pins each in both tiers, so unprovableClauses carries it
      //       rather than a fixture here. The atServer never follows the
      //       replacement edge: a successor is its predecessor's sibling,
      //       settled at its own first authentication. And the exclusion set is
      //       the ONE revoked id, never a client-walked subtree — an exclusion
      //       set binds only the client that computes it, while approval state
      //       is consulted by every roster query on every client.
      provenIn('packages/at_client/test/nskey_rotation_test.dart',
          'rotates every granted namespace, excluding the revoked id',
          proves: 'the exclusion set the client hands every push: exactly the '
              'one id named, over an atSign granted four namespaces and two '
              'rotations. `everyElement` is the point - a build that widened '
              'the set from the atServer\'s cascade, or from a client-side '
              'walk, would put a second id in one of them',
          clauses: ['exclusion set stays the ONE']);
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
            'exclusion set stays the ONE',
          ]);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when this enrollment comes to hold its own generation G2, then its '
              'next write cuts a fresh key sealed to G2',
          proves: 'the sending side of the cut: a remaining enrollment\'s next '
              'share is under a fresh key whose sibling copy the superseded '
              'generation fails to open, with the new generation\'s private as '
              'the positive control. UC-A5.7 carries the rest of that row',
          clauses: ['generations E2 never held']);
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
      provenIn('packages/at_client/test/ck_collection_test.dart',
          'a superseded key a record still cites is kept',
          proves: 'the half a reader is most likely to get backwards: the '
              'collection a rotation queues keeps a key while a record cites '
              'it, which is what lets a later joiner read what was written '
              'before it',
          clauses: ['kept while any record cites it']);
      provenIn('packages/at_client/test/ck_collection_test.dart',
          'a rotation collects the key it superseded, which nothing cites',
          proves: 'and deletes both conveyances of one nothing cites, which '
              'only the enrollment that cut it may do',
          clauses: [
            'deleted by the enrollment that cut it once neither holds'
          ]);
      provenIn(
          'tests/at_functional_test/test/content_key_rotation_live_test.dart',
          'a superseded key is kept while a record cites it, and collected '
              'once none does',
          proves: 'both halves against a live atServer: the key survives the '
              'rotation while a record cites it, and once that record is '
              'deleted the collection removes its conveyance from the '
              'atServer and keeps the current one',
          clauses: [
            'deleted by the enrollment that cut it once neither holds'
          ]);
      provenIn(
          'tests/at_functional_test/test/content_key_rotation_live_test.dart',
          'a key the policy replaces is collected at the next caught-up sync',
          proves: 'the POLICY route reaches the same place live: a policy that '
              'says yes replaces the key, the replacement\'s collection is '
              'refused while its own writes push, and at the next sync that '
              'catches up the uncited key leaves the atServer',
          clauses: [
            'deleted by the enrollment that cut it once neither holds'
          ]);
      provenIn('packages/at_client/test/ck_collection_test.dart',
          'defaults to 8 days',
          proves: 'the default grace as a raw-literal pin on the config an '
              'application builds without naming one',
          clauses: ['8 days by default']);
      provenIn('packages/at_client/test/ck_collection_test.dart',
          'counts from the cut of its successor, not its own',
          proves: 'the grace runs from the replacement, not the key\'s age: a '
              'key cut a month ago and replaced yesterday is kept, and goes '
              'once its successor is 9 days old',
          clauses: ['after the cut of the key that replaced it']);
      provenIn(
          'tests/at_functional_test/test/content_key_rotation_live_test.dart',
          'by default, a superseded key nothing cites is kept for its grace',
          proves: 'live, with the default config: an uncited superseded key '
              'stays on the atServer, and the same key goes at once under no '
              'grace, so it was the grace that kept it',
          clauses: ['8 days by default']);
      provenIn('tests/at_functional_test/test/content_key_grace_live_test.dart',
          'a notification sent under a key that is then replaced still opens',
          proves: 'why the grace exists, end to end: a recipient offline while '
              'its key was replaced opens the notification afterwards, and '
              'with no grace the same open fails',
          clauses: [
            'so a recipient can still open a notification sent under it'
          ]);
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'the period is 365 days, pinned as a literal',
          proves: 'the default period as a raw-literal pin rather than a '
              'round trip through the constant that defines it, so an '
              'intended change edits the pin and that edit is the review',
          clauses: ['`rotateCkAfterOneYear`']);
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'every config the SDK builds carries the yearly defaults',
          proves: 'that it IS the default: CryptoConfig, CryptoConfig.nskey '
              'and readsNskeyWritesLegacy all hand it to an application that '
              'names none, and the era default is built through the second',
          clauses: ['`rotateCkAfterOneYear`']);
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'a key a year old or older is replaced',
          proves: 'the boundary is INCLUSIVE, which is the arm an off-by-one '
              'would silently move');
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'a key younger than a year is left alone',
          proves: 'the other side of the boundary');
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'age is measured against the now it is given, not the clock',
          proves: 'that `now` is a parameter rather than a read, which is what '
              'makes an application\'s policy testable without a clock');
    });

    test(
        'UC-A5.5 \u00b7 the namespace-key lever is asked at exactly two points',
        () {
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
      //       yes mints, retains and conveys; the default is a year.
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
          'the period is 365 days from the advertised mint, pinned as a literal',
          proves: 'the default period and its inclusive boundary as raw '
              'literals, measured from the advertisement\'s own mint date',
          clauses: ['`rotateNskeyAfterOneYear`']);
      provenIn('packages/at_client/test/rotation_policy_test.dart',
          'every config the SDK builds carries the yearly defaults',
          proves: 'that it IS the default every config the SDK builds hands '
              'an application that names none',
          clauses: ['`rotateNskeyAfterOneYear`']);

      // NOTE: "there is no third ask" is deliberately UNPINNED, being an
      //       absence: `AtClient.ensureReachable` cannot reach the policy,
      //       because it returns alreadyReachable in exactly the branch where a
      //       generation is published, and that is the only branch
      //       `seedNamespace` consults the policy in. Asserting it would mean
      //       driving a whole AtClientImpl.
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
          'seeding follows the posture, and the shipped default does not seed',
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

    test('UC-A5.7 \u00b7 a content key follows both namespace keys it rests on',
        () {
      // GIVEN E1's content key toward @bob has its sibling copy sealed to
      //       Alice's generation G1.
      // WHEN  a revocation rotates Alice's own namespace key to G2, and E1
      //       writes to @bob again.
      // THEN  a fresh key sealed to G2, which G1 does not open; inside the
      //       window the key is kept and the private asked for; the policy is
      //       not asked; a restart resumes only a pointer naming both
      //       generations.
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when this enrollment comes to hold its own generation G2, then its '
              'next write cuts a fresh key sealed to G2',
          proves: 'the replacement, the sibling copy\'s recorded generation, '
              'and that G1\'s private fails to open it while G2\'s opens it — '
              'the open is the clause, so it is asserted on the ciphertext '
              'rather than on the metadata alone',
          clauses: ['the value cites a fresh content key whose sibling copy']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when two writes start at once after G2 arrives, then they cut one '
              'fresh key, which @bob opens',
          proves: 'one fresh key across two racing writes, counted on what '
              'was conveyed, and @bob\'s private opening its conveyance',
          clauses: ['two writes E1 starts at once']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when G2 is advertised but its private has not reached this '
              'enrollment, then its next write keeps the current key',
          proves: 'the advertisement-first order: no conveyance while the '
              'private is missing, then a fresh key on the write after it '
              'arrives',
          clauses: ['E1 keeps its current key and asks']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when G2\'s private arrives before its advertisement, then the key '
              'is kept until G2 is advertised too',
          proves: 'the private-first order, on a ring that goes on answering '
              'with G1 the way a client does before sync lands G2',
          clauses: ['whichever arrived first']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when @bob rotates and the next write needs a fresh key, then it '
              'succeeds with a sibling copy sealed to G1',
          proves: 'a cut inside the window succeeds, its sibling copy sealed '
              'to the generation the replaced key rested on, and the next '
              'write after the private arrives moves to G2',
          clauses: ['A write that needs a fresh key meanwhile succeeds']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when it first writes to another destination, then that key\'s '
              'sibling copy rests on G1 too',
          proves: 'that "the generation E1\'s keys in `buzz` already rest on" '
              'is read across destinations, not only from the key replaced',
          clauses: ['A write that needs a fresh key meanwhile succeeds']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when nothing in the namespace records an own generation, then the '
              'share goes without a sibling copy, and a key with one follows G2',
          proves: 'the no-copy arm, and that it is temporary',
          clauses: ['A write that needs a fresh key meanwhile succeeds']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when it restarts with a pointer written before the own generation '
              'was recorded, then it cuts a fresh key rather than resuming',
          proves: 'the case where only the field\'s absence refuses the '
              'resume: inside the window no own generation is held to '
              'compare with',
          clauses: ['A pointer written before it recorded']);
      provenIn('packages/at_client/test/nskey_self_heal_test.dart',
          're-derives a generation it holds from the filed seed',
          proves: 'what a window copy is sealed to on a real ring: the public '
              'half re-derived from the filed seed, which a seed filed under '
              'some other kid does not pass',
          clauses: ['A write that needs a fresh key meanwhile succeeds']);
      provenIn('packages/at_client/test/nskey_self_heal_test.dart',
          'a miss on an own generation fires the injected ask, once',
          proves: 'the asking half: `CkManager` checks an own generation '
              'through `privateHalf`, and a miss there sends the request to '
              'the atSign\'s other enrollments. The composition of the two is '
              'read, not run, in-process',
          clauses: ['E1 keeps its current key and asks']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when the rotation policy always answers no, then a move to G2 '
              'still cuts a fresh key',
          proves: 'the replacement with a policy that refuses, which the '
              'control shows was asked while nothing had moved and not asked '
              'once G2 had',
          clauses: ['does not stop the replacement']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when this enrollment restarts, then it resumes the key only while '
              'its pointer names the own generation it holds',
          proves: 'a resume while both generations match, and a fresh key '
              'after a restart that finds G2 held',
          clauses: ['names both generations as current']);
      provenIn(
          'packages/at_client/test/ck_manager_test.dart',
          'when its pointer was written before the own generation was '
              'recorded, then a restart cuts a fresh key',
          proves: 'that a pointer naming no own generation is not resumed '
              'once the sender holds one',
          clauses: ['A pointer written before it recorded']);
      provenIn(
          'packages/at_client/test/current_ck_pointer_test.dart',
          'written before the own generation was recorded, reads as '
              'recording none',
          proves: 'the read half: such a pointer is parsed as one that '
              'recorded no own generation, which is what the resume refuses',
          clauses: ['A pointer written before it recorded']);
    });
  });
}
