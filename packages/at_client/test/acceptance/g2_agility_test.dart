/// G2 · Crypto agility — add, never replace.
///
/// All three advertisements — an enrollment's key package, a namespace's nskey
/// generation, and an enrollment's `_apsk` — are arrays so that an algorithm
/// upgrade is an ADD by the advertiser rather than a coordinated flag day.
///
/// The signature case is not the encryption case: for encryption the SENDER
/// picks from the recipient's advertised set, so offering two costs the
/// advertiser nothing; for a signature the SIGNER picks and the verifier must
/// cope with whatever arrives, so only a plural signature covers a verifier gap.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 17.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('G2 · crypto agility', () {
    test('UC-G2.1 · a key package reader keeps the entry it cannot use', () {
      // GIVEN a key package advertising two keys, one under an alg this build
      //       does not implement, beside a malformed and a non-map entry.
      // WHEN  this build reads it and picks a key to seal to.
      // THEN  the known key is selected under the CALLER's order; the unknown
      //       entry is kept; malformed entries are skipped; a package naming no
      //       suites is refused.
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'unknown-alg entries are kept, malformed entries skipped, bestKeyFor ',
        proves:
            'all three tolerance arms over ONE payload holding an unknown-alg '
            'entry, a known one, a malformed entry and a non-map entry at once '
            '- so a reader coping with them separately but not together would '
            'still fail. The unknown entry is KEPT rather than dropped, which '
            'is what lets a later build of this same package use it; and '
            'bestKeyFor is asked twice with different caller orders over the '
            'same package, so the answer moves with the caller, not the package',
        clauses: [
          'the package states what the holder can open, the caller states what it prefers',
          'an entry whose `alg` this build does not know is **kept**, never dropped',
          'a malformed entry is **skipped** and a non-map entry ignored',
        ],
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a package that names no suites is refused, not read as the oldest',
        proves: 'that an ABSENT suites list is refused rather than defaulted. '
            'Reading it as the oldest construction is the permissive direction, '
            'and would let a holder be sealed to under something it never '
            'claimed to open',
        clauses: ['a package naming **no** `suites` is **refused**'],
      );
      provenIn(
        'packages/at_auth/test/wire_literal_pins_test.dart',
        'the kid is the SHA-256 prefix of the key BYTES, one function',
        proves: 'that a kid cannot be reassigned, which is what makes an add '
            'distinguishable from a replace at read time. Pinned against a '
            'digest computed OUTSIDE this tree - a python one-liner in the '
            'test comment - so the assertion cannot follow the implementation '
            'it checks; and both spellings are asserted to be one derivation '
            'rather than two, so a build cannot address the same key two ways',
        clauses: [
          'an entry is addressed by its `kid`, and a `kid` is a function of the key itself'
        ],
      );
    });

    test('UC-G2.2 · an nskey advertisement reader walks the list', () {
      // GIVEN a signed nskey advertisement whose keys list carries an unusable
      //       entry FIRST.
      // WHEN  a sender resolves it to seal to.
      // THEN  the usable entry is found; an advertisement of only unusable
      //       entries is refused; one that retires every key it names is too.
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'an entry this build cannot use is skipped, not fatal',
        proves:
            'the walk, and the ORDER is the assertion: the unusable entry is '
            'placed first, so a reader that took the head rather than walking '
            'goes red here and would pass on a list ordered the other way',
        clauses: [
          'the usable entry is found although an unusable one precedes it'
        ],
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'an advertisement of only unusable entries is refused',
        proves:
            'the refusal and its direction: with nothing usable there is no '
            'target, and inventing one would produce a record the owner can '
            'never open - a loss that surfaces at the far end and names nobody',
        clauses: [
          'an advertisement of **only** unusable entries is **refused**'
        ],
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'an advertisement that retires every key it names is refused',
        proves:
            'the case a reader counting ENTRIES rather than live ones would '
            'miss: the document is well formed and its keys list is not empty, '
            'and there is still nothing to seal to',
        clauses: [
          'an advertisement that **retires every key it names** is refused'
        ],
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'a tampered advertisement is rejected',
        proves:
            'the ORDER of the two operations, which is the security property: '
            'the signature over the whole document is verified before any key '
            'is read out of it, so neither adding a weak entry nor stripping a '
            'strong one survives. A reader that parsed first and verified '
            'afterwards would pass every functional assertion in this row and '
            'still be editable in transit',
        clauses: [
          'the APKAM signature over the document is checked before a single key is read out of it'
        ],
      );
    });

    test(
        'UC-G2.3 · an _apsk reader tolerates an unknown alg and distrusts an unknown status',
        () {
      // GIVEN an _apsk array carrying an unknown-alg entry beside an rsa2048
      //       one; and separately an entry with an unknown status token.
      // WHEN  a verifier parses it.
      // THEN  the known entry is used; an array of nothing understood is
      //       refused; an unknown STATUS is not a verification candidate, which
      //       is the opposite of how an unknown ALG is treated.
      provenIn(
        'packages/at_client/test/apsk_formats_test.dart',
        'an array skips what it cannot use and reads what it can',
        proves: 'the tolerance arm: an entry under an alg this build has never '
            'heard of sits beside an rsa2048 one, and the parse returns the '
            'rsa2048 key and its public half rather than refusing the document',
        clauses: ['the array is not refused for carrying the other'],
      );
      provenIn(
        'packages/at_client/test/apsk_formats_test.dart',
        'an array of nothing understood is refused, not fallen back from',
        proves: 'that the refusal is the answer rather than a fallback. A '
            'signature checked against a key derived some other way attests to '
            'nothing, so there is no safe default available here',
        clauses: ['an array of **nothing understood** is refused'],
      );
      provenIn(
        'packages/at_client/test/apsk_formats_test.dart',
        'a status this build cannot read is NOT a verification candidate',
        proves: 'the asymmetry, which is this row\'s reason for existing. An '
            'unknown ALG is skipped and the document trusted; an unknown '
            'STATUS removes its entry from consideration. Reading an unknown '
            'status as retired would be permissive in exactly the wrong '
            'direction - a retired key still verifies what it signed, so an '
            'older build would go on trusting a key its owner has disowned',
        clauses: [
          'an unknown `status` is treated as the opposite of an unknown `alg`'
        ],
      );
      provenIn(
        'packages/at_client/test/wire_literal_pins_test.dart',
        'an unrecognised status is carried through, not flattened',
        proves:
            'the carry-through, which is the half that matters where a record '
            'is REBUILT rather than edited: the advertisement is composed '
            'afresh on every reconcile from stored state, so a build that '
            'flattened an unknown token on the way out would republish the '
            'owner as saying something weaker than they said, silently',
        clauses: ['carried through **verbatim** rather than flattened'],
      );
      provenIn(
        'packages/at_client/test/apsk_formats_test.dart',
        'one active rsa2048 key is spelled bare, not as the array',
        proves:
            'the bare spelling, and it is cited WITH its discriminator: the '
            'very next arm, "a second key forces the array - so the assertion '
            'above discriminates", exists because a test that only ever saw '
            'one key could not tell a bare-always writer from a correct one. '
            'The pair is what makes an ADD a shape change rather than a length '
            'change',
        clauses: ['whose wire SHAPE changes with the number of entries'],
      );
    });

    test('UC-G2.4 · an add moves nothing peers already address', () {
      // GIVEN an advertiser whose peers already seal or verify against its one
      //       existing entry; a second algorithm is configured.
      // WHEN  the advertiser adds a key for it.
      // THEN  the existing entry keeps its kid and stays active, what was
      //       already sealed to it still opens, and `suites` widens.
      provenIn(
        'tests/at_functional_test/test/key_package_amendment_live_test.dart',
        'UC-A2.5 · an enrollment amends its own key package',
        proves:
            'the add itself against a live atServer: a package advertising one '
            'key gains a second by enroll:update, and the original kid is still '
            'present exactly once and still active. suites covers both KEMs, '
            'derived from the package\'s own keys rather than from what the '
            'writing build supports',
        clauses: [
          'the existing entry keeps its `kid` and stays **`active`**',
          'the advertisement\'s `suites` **widens**',
        ],
      );
      provenIn(
        'tests/at_functional_test/test/key_package_amendment_live_test.dart',
        'UC-A2.5 · an envelope sealed before the amendment still opens after it',
        proves:
            'the half that makes an add safe rather than merely possible. A '
            'build treating a replaced kid as retired would pass every '
            'write-side assertion and lose, silently and unattributably, a '
            'secret that was correctly sent',
        clauses: ['still opens or verifies afterwards'],
      );
      provenIn(
        'packages/at_client/test/signing_key_minting_test.dart',
        'a re-minted algorithm is advertised beside the key it replaced',
        proves:
            'the signing side of the same property: the returning algorithm '
            'lands beside its retired predecessor rather than displacing it, so '
            'the advertisement grows where a naive writer would overwrite',
      );
    });

    test('UC-G2.5 · an nskey rotation mints fresh and carries nothing forward',
        () {
      // GIVEN a generation holding keys for one or more algorithms, and a
      //       rotation due by age policy or because it predates a revocation.
      // WHEN  a client takes the mint lock and rotates.
      // THEN  the new generation holds only material minted now; an algorithm
      //       nobody still runs never returns; a revoked enrollment gains
      //       nothing; every kid changes, which is how peers learn.
      //
      // ⛔ WHOLLY UNPINNED, deliberately. Today's rotation mints ONE key, under
      // keyEstablishmentAlgorithms.first, so "carries nothing forward" is
      // trivially true of it and proves nothing about the ruled behaviour -
      // which is about a generation that can hold several. Nothing citable here
      // would go red if the ruling were implemented wrongly. See decisions.md
      // 119 item 2.
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'the published advertisement emits its exact wire shape — raw literals',
        proves:
            'ONLY the wire shape as it stands: hand-written raw literals over a '
            'keys list of length one. It is named here as the test that goes '
            'RED the day the mint stops taking the first configured algorithm, '
            'which is the signal this row waits for - not as evidence for any '
            'clause above',
      );
      provenIn(
        'packages/at_client/test/nskey_rotation_test.dart',
        'publishes a fresh generation and keeps the superseded private',
        proves: 'that no key in the successor is one the predecessor carried '
            '- compared at the advertised keys themselves rather than at the '
            'kids, which are derived from those keys and so say something '
            'about the derivation instead. The predecessor is asserted '
            'non-empty first, because two empty lists intersect emptily and '
            'would read as a clean rotation. Mutation-proven: carrying the '
            'superseded keys into the successor reddens it. ⚠️ It is one key '
            'per generation today, so this is the single-algorithm case of '
            'the clause. ⚠️ That caveat is spent: the mint went plural on '
            '2026-08-28 and the sibling arm below runs the same assertion '
            'over two algorithms',
        clauses: [
          'a revoked enrollment gains nothing from the rotation',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_rotation_test.dart',
        'a rotation mints the whole configured set afresh',
        proves: '"whatever algorithms that generation named", which could not '
            'be asserted while a generation held one key: a client configured '
            'for both mints both, rotates, and NO key in the successor is one '
            'the predecessor carried - compared at the advertised keys, with '
            'the predecessor asserted non-empty because two empty lists '
            'intersect emptily. A rotation that carried one algorithm forward '
            'would hand an excluded enrollment a key it already held',
        clauses: [
          'the new generation holds **only** material this client minted now',
        ],
      );
      provenIn(
        'packages/at_client/test/ck_manager_test.dart',
        'cuts a fresh CK when the destination has rotated its nskey',
        proves: 'the peer half, at the mechanism CkManager.ensureCurrent uses: '
            'the cached CK is kept beside the generation kid it was sealed to, '
            'the advertised kid changes, and the next ensureCurrent cuts and '
            'conveys a second CK rather than reusing the first. That is the '
            'only signal a sender gets - it never sees a recipient fail to '
            'decapsulate - and the first ensureCurrent runs as the control, '
            'so a build that cut a fresh CK on every call would fail the '
            'already-current arm beside it',
        clauses: [
          'every peer\'s cached content key is superseded',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_rotation_test.dart',
        'does not push to an excluded enrollment',
        proves: 'the other half of the same clause: the exclusion reaches the '
            'ROSTER QUERY rather than being remembered by the caller, so the '
            'excluded enrollment is never sealed the successor and is left '
            'holding the previous generation only',
        clauses: [
          'a revoked enrollment gains nothing from the rotation',
        ],
      );
    });

    test('UC-G2.6 · a client adds its own missing algorithm to the generation',
        () {
      // GIVEN a current generation lacking an algorithm this client needs.
      // WHEN  this client mints that material and adds it.
      // THEN  it joins the CURRENT generation in place, under the same mint
      //       lock; nothing already there moves; only the new private is
      //       conveyed.
      //
      // ⚠️ This block said "there is no add operation at all, not even behind
      // a flag" until 2026-08-28, when PublishedNskeyKeyRing.add landed. Three
      // clauses are pinned below; what stays unpinned is c4 (only the new
      // private is conveyed) and c6 (the added document is re-signed by the
      // adding enrollment), neither of which any assertion reaches yet.
      provenIn(
        'packages/at_client/test/nskey_rotation_test.dart',
        'joins the current generation in place, keeping its identity',
        proves: 'the in-place half, over the rollout-1 case the row describes: '
            'a generation minted by a build configured for one algorithm, and '
            'the same install upgraded to a build configured for two. The '
            'existing entry keeps its kid and its key bytes, and the '
            'generation keeps its createdAt - refreshing that would make a '
            'generation minted before a revocation read as one minted after, '
            'and the rotation that revocation is owed would never fire. One '
            'fixture with a swappable preference, because two fixtures have '
            'two APKAM keypairs and the second cannot verify the first\'s '
            'advertisement',
        clauses: [
          'the material joins the **current** generation in place',
          'everything already in the generation is untouched',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_rotation_test.dart',
        'a client that loses the mint lock adds nothing',
        proves: 'that the add takes the SAME lock and writes nothing when it '
            'loses: the lock is taken by another enrollment between this '
            'client deciding to add and getting there, and the add publishes '
            'no record at all. Its control is the mint that preceded it in the '
            'same fixture, so an add that wrote nothing because the fixture '
            'was inert would fail that first',
        clauses: [
          'the add takes the **same mint lock** as a rotation',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_rotation_test.dart',
        'an unmintable set never reaches the mint — the preference refuses it',
        proves:
            'where the "only what it implements" rule is actually enforced, '
            'which is not in the ring: AtClientPreference refuses an algorithm '
            'this build does not implement, and an empty list, both at '
            'construction. Asserted here so that the ring having no guard of '
            'its own is a decision rather than an oversight - a repeated check '
            'there would be unreachable, and would be a claim about this class '
            'rather than a check',
        clauses: [
          'a client can only add material for an algorithm it implements',
        ],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_mint_lock_live_test.dart',
        'two CONCURRENT mints by one enrolment publish one advertisement',
        proves:
            'that the interlock this row depends on actually prevents the lost '
            'update, live: two concurrent writers reach one advertisement '
            'rather than one overwriting the other. That is the exact hazard an '
            'add creates - read, mutate, write on shared durable state - so the '
            'add takes this lock rather than a new one. It is evidence for the '
            'lock, not for any clause above',
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'a tampered advertisement is rejected',
        proves: 'that the signature is verified per DOCUMENT rather than per '
            'generation: the reader resolves the signer from the envelope kid '
            'and checks it before reading a key. That is what makes an add '
            'signable by an enrollment other than the one that minted the '
            'generation - nothing in the read path assumes one signer per '
            'generation, and this is the arm that would go red if one were '
            'introduced',
      );
      provenIn(
        'tests/at_functional_test/test/nskey_mint_lock_live_test.dart',
        'a client that meets another holder\'s lock refuses to mint',
        proves:
            'the back-off half: a client meeting a held lock refuses rather '
            'than proceeding, which is what makes "fails the lock, backs off '
            'and re-reads" a behaviour rather than an intention',
      );
      provenIn(
        'packages/at_client/test/nskey_seeding_test.dart',
        'exactly the new kid, and not the one already there',
        proves:
            'the conveyance selection, measured as a COUNT rather than as a '
            'membership: `_addMissing` is driven over a generation carrying '
            'one algorithm and an add that returns it carrying two, and the '
            'kids it attempts to convey are recorded. It attempts exactly one '
            '— the kid the add minted — so a re-send of what the fleet '
            'already holds would show as a second entry rather than being '
            'invisible. Its zero-case sibling drives an add that added '
            'nothing and asserts no conveyance at all; a mutation removing '
            'the "skip what was already there" filter reddens both, naming '
            'the extra kid',
        clauses: ['private is conveyed to authorised enrollments'],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'UC-G2.6 c6 \u00b7 the added document is re-signed by the ADDING enrollment',
        proves: 'the generation is signed by one enrollment and added to by '
            'another, and the republished envelope carries the ADDER\'s kid. '
            'Both halves are asserted: a control reads the signer off the '
            'document before the add and finds the minter, so the assertion '
            'measures a change rather than a constant. A mutation making the '
            'signer claim another enrollment reddens it naming both ids',
        clauses: ['re-signed by the adding enrollment'],
      );
    });

    test(
        'UC-G2.7 · a retired entry stops being offered and still opens history',
        () {
      // GIVEN an advertiser that has retired an entry — the _apsk swap at
      //       pqActive, or a rotated nskey generation.
      // WHEN  a new operation runs, and separately an old record is read.
      // THEN  the retired entry is not selected for anything new, stays
      //       advertised, and what it produced still verifies or opens.
      provenIn(
        'packages/at_client/test/jws_envelope_test.dart',
        'an envelope signed by the retained key still verifies',
        proves:
            'the history half at its narrowest: an `_apsk` carrying TWO mldsa65 '
            'entries, one active and one retired, and an envelope signed by the '
            'retired one. The verifier walks every key advertised under the '
            'resolved algorithm rather than trying only the current one — its '
            'sibling arm pins the refusal message naming how many keys were '
            'tried, so a verifier that stopped at the first would go red',
        clauses: ['it stays **advertised**'],
      );
      provenIn(
        'packages/at_client/test/signing_key_minting_test.dart',
        'an envelope written AFTER the withdrawal carries no signature of it',
        proves:
            'the other direction, which is the one an over-eager reading of the '
            'clause above would break: retiring a key must stop it signing '
            'while leaving it verifying. A build that kept a retired key in the '
            'signing set would pass every verification assertion',
        clauses: ['the retired entry is **not selected** for anything new'],
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'a retired entry is not what a sender is pointed at',
        proves:
            'the nskey arm of the same asymmetry, over an advertisement holding '
            'a retired X-Wing entry beside an active ML-KEM one, arranged so '
            'that preference order ALONE would pick the retired key. A selector '
            'consulting only the sender\'s order fails here',
      );
    });

    test('UC-G2.8 · a verifier resolves the algorithm, then walks the keys',
        () {
      // GIVEN an _apsk advertising more than one key under the algorithm an
      //       envelope is signed with - the ordinary state of any enrollment
      //       that has ever rotated its signing key.
      // WHEN  a verifier checks the envelope.
      //
      // ⛔ The key-identifier clauses are UNPINNED: decisions.md 119 item 4
      // rules that a signature names the key it was made with, and no such
      // field exists. What IS pinned is the fallback the ruling preserves - the
      // walk, and its counted refusal - because that is what an older verifier
      // goes on doing once the field ships, unbumped, beside it.
      // THEN  it resolves the algorithm from what the two documents share and
      //       walks every key advertised under it, current first; the refusal
      //       names how many were tried.
      provenIn(
        'packages/at_client/test/signing_key_minting_test.dart',
        'an envelope signed before the withdrawal still verifies',
        proves: 'the ordinary case rather than the overlap: a real '
            'reconcileSigningKeys() moving the in-use set from {rsa2048} to '
            '{mldsa65} — a SINGLE-signing app, at a stage the ladder ships — '
            'and an envelope written before the move still verifying against '
            'the advertisement afterwards. It is what makes the plural _apsk a '
            'property of every deployment that has ever rotated rather than of '
            'the ones that opt into two signatures',
        clauses: ['this is the ordinary case, not the overlap case'],
      );
      provenIn(
        'packages/at_client/test/jws_envelope_test.dart',
        'a signature under neither key is still refused',
        proves:
            'that the match is by TRIAL rather than by name, and that every '
            'advertised key under the resolved algorithm is reached: the '
            'refusal message counts them — "does not verify against any of the '
            '2 mldsa65 key(s)". A verifier that stopped at the first key would '
            'report a bad signature here instead, so the count is what '
            'distinguishes walking from guessing',
        clauses: ['names how many were tried'],
      );
      provenIn(
        'packages/at_client/test/jws_envelope_test.dart',
        'and however the ADVERTISEMENT is ordered',
        proves: 'that NEITHER document\'s ordering decides. Its sibling arm '
            'varies the envelope\'s signature order; this one varies the '
            '_apsk\'s, which every arm of that group had published RSA-first. '
            'A corrupt RSA signature beside an intact ML-DSA one verifies '
            'under both orderings, because the stronger shared algorithm is '
            'what gets checked and the corrupt entry is never reached. '
            'Mutation-proven: resolving by the advertisement\'s order instead '
            'of by strength reddens it, quoting "the envelope\'s rsa2048 '
            'signature does not verify"',
        clauses: ['the algorithm is identified, never guessed'],
      );
    });

    test('UC-G2.9 · step 3 has no lever, so a retired key verifies forever',
        () {
      // GIVEN an _apsk advertising a retired key beside its active one.
      // WHEN  a verifier checks an envelope, and separately an attacker who has
      //       broken the retired algorithm presents one signed under it.
      // THEN  the verifier cannot decline an algorithm it implements, so the
      //       retired key is a standing forgery surface; step 3 would close it
      //       and has no lever.
      provenIn(
        'packages/at_client/test/apkam_signing_keys_test.dart',
        'one signature per held key, all naming this enrollment',
        proves: 'the count, from held key material: an enrollment holding two '
            'signing keys emits two signatures, under ML-DSA-65 and RS256. '
            'This is the mechanism the overlap would use',
        // ⛔ Clause fragment WITHDRAWN 2026-08-28 with the overlap it
        // described - see decisions.md 120. The arm still pins the count from
        // held material, which is what the removal will change.
      );
      provenIn(
        'packages/at_client/test/signing_key_minting_test.dart',
        'a two-member in-use set signs twice, and a one-algorithm verifier ',
        proves: 'the row\'s central claim, and it rested on nothing until '
            '2026-08-28: a two-member dataSigningKeyAlgorithms driven through '
            'reconcileSigningKeys and the production selector produces a '
            'two-signature envelope, and an _apsk advertising only ONE of the '
            'two - the record as it stood before the second algorithm was '
            'minted, which is what an un-upgraded verifier would be served - '
            'still verifies it. A single-member control runs first, so the '
            'pair is attributable to the SET rather than to this client always '
            'signing with everything it holds. Mutation-proven: making the '
            'selector return only the strongest held key reddens the '
            'two-signature assertion by its own reason string and leaves the '
            'control green',
        // ⛔ Clause fragments WITHDRAWN 2026-08-28. This pinned two clauses
        // about the two-signature overlap, and decisions.md 120 retired the
        // overlap: the three-step ladder replaces it, because double-signing
        // covers nothing a verifier can insist on. The test is KEPT and
        // untouched - it pins the multi-signature writer as it stands, so it
        // goes red the day that writer is removed, which is the signal.
      );
      provenIn(
        'packages/at_client/test/jws_envelope_test.dart',
        'the writer emits one signature per key, over one payload',
        proves:
            'that the several signatures cover ONE payload rather than several '
            'documents, which is what makes a verifier free to pick whichever '
            'algorithm it shares. Its sibling arms pin that a valid RSA '
            'signature does not rescue a corrupt ML-DSA one, so "pick one that '
            'verifies" is not the rule — the strongest shared is',
      );
      provenIn(
        'packages/at_client/test/jws_envelope_test.dart',
        'no shared algorithm names BOTH documents, and does not fall back',
        proves: 'the refusal names what the envelope carries AND what the '
            '_apsk advertises, over UC-G2.9\'s own case rather than a '
            'relabelling: an ML-DSA envelope against an RSA-only '
            'advertisement, which is what a peer that has not taken the '
            'transition sees. Its control is the same envelope verifying '
            'against an _apsk that does advertise ML-DSA, so a build refusing '
            'every ML-DSA envelope would satisfy the refusal and fail the '
            'control. Mutation-proven: dropping the envelope\'s side from the '
            'message reddens it',
        clauses: [
          'a verifier sharing **no** algorithm with the envelope is refused',
        ],
      );
      // ⛔ The rest of this row's clauses are UNPINNED because the lever they
      // describe does not exist: there is no accepted-algorithms set anywhere
      // in AtClientPreference, so a verifier cannot decline an algorithm it
      // implements and nothing can assert that it does. See decisions.md 120.
      //
      // The citations above are kept deliberately. They pin the multi-signature
      // WRITER as it stands, so they go red the day it is removed — which
      // decisions.md 120 makes possible and a separate plan row tracks.
      //
      // ⚠️ This block used to say the row's central claim "rests on nothing"
      // because no test drove a two-member preference through to an envelope.
      // One was written on 2026-08-28 and then the row changed underneath it:
      // the overlap it proved is retired, so the test now pins behaviour the
      // design has moved away from rather than behaviour it relies on.
    });

    test('UC-G2.10 · the ladder across atSigns: safe through rollout 1', () {
      // GIVEN @bob upgrades and publishes a widened advertisement; @alice is
      //       still on the old build.
      // WHEN  alice1 shares toward @bob, and @bob reads it.
      // THEN  the old alice seals under the entry it understands and bob opens
      //       it; an upgraded alice seals under the new entry immediately, with
      //       no further release on bob's side.
      provenIn(
        'tests/at_functional_test/test/key_package_amendment_live_test.dart',
        'UC-A2.5 · a sender picks by its own order and stamps the matching ',
        proves: 'the upgraded half, live and as a differential: one recipient '
            'advertising two KEMs, two senders differing ONLY in their own '
            'sealsToKeyAlgorithms order, each sealing under the one it prefers '
            'and stamping the matching version byte. Because the two arms share '
            'a recipient and differ in one field, a sender that ignored the '
            'advertisement would make both arms agree',
        clauses: ['seals under the new entry **immediately**'],
      );
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
        'the SENDER\'s order decides, not the recipient\'s',
        proves:
            'that the choice is the sender\'s to make within what the recipient '
            'offers — both lists hold both suites in opposite orders, and '
            'swapping the arguments swaps the answer. An un-upgraded sender '
            'therefore takes what it knows without the recipient being asked',
      );
      provenIn(
        'packages/at_client/test/nskey_resolver_test.dart',
        'a narrowed list refuses, and the message names both sides',
        proves: 'the rollout-2 refusal: a sender whose sealsToKeyAlgorithms '
            'names only the algorithm the recipient never added is refused '
            'BEFORE anything is written, with a message naming what it will '
            'seal to, what the recipient advertises, and the preference that '
            'decided. Its sibling arm - the same owner resolving under the '
            'default list - is the control, so the refusal is the narrowing '
            'and not a cold start',
        clauses: [
          'is refused before anything is written',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_resolver_test.dart',
        'a widened advertisement serves each sender the entry IT understands',
        proves: 'the SELECTION half, as a differential over one advertisement '
            'carrying both algorithms: a sender narrowed to either one is '
            'served that entry and its key. Run as a pair because neither '
            'narrowing proves anything alone - a build that always chose '
            'x-wing satisfies the first arm and one that always chose ml-kem '
            'satisfies the second. Every other arm on this row varies the '
            'sender\'s ORDER across algorithms both builds hold; these give '
            'it a list of ONE, which is what a build that cannot use the '
            'other entry looks like from here',
        clauses: [
          'seals under the entry it understands',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
        'either entry seals and opens, and each stamps its OWN kid',
        proves: 'the other half - that the recipient opens it - over the same '
            'widened advertisement, both directions, with the private for '
            'each entry. ⛔ BOTH ARMS REFUSED until 2026-08-28: NskeyProvider '
            'asked the advertisement which algorithm it was, and that getter '
            'answers for the single entry a sender with no preference would '
            'take. The stamped kid is asserted BEFORE the round trip, or a '
            'wrong kid reddens as a decapsulation error instead of on its own '
            'terms; mutation-proven separately on each',
        clauses: [
          'seals under the entry it understands',
        ],
      );
      // ⛔ One clause is UNPINNED. "The recipient does nothing further" is an
      // absence - no re-seal, no conveyance fired - and the amendment test
      // proves only the consequence, that an envelope sealed BEFORE still
      // opens after. An absence needs its own arm, and a test that merely
      // succeeds at reading is satisfied either way.
    });

    test('UC-G2.11 · the ladder within one atSign: safe through rollout 1', () {
      // GIVEN @alice has two enrollments sharing a namespace. alice1 runs the
      //       app's ROLLOUT 1 build - mints both algorithms, seals only to the
      //       old. alice2 is still on the previous build.
      // WHEN  alice1 writes a self record alice2 reads, and then the reverse.
      // THEN  both directions succeed, so rollout 1 can be taken one install at
      //       a time; and after ROLLOUT 2 an install that never took rollout 1
      //       is refused, which is the ladder working rather than a defect.
      provenIn(
        'packages/at_client/test/nskey_resolver_test.dart',
        'the default reaches an owner advertising either KEM',
        proves:
            'the resolver half in process: a default-configured client resolves '
            'an owner advertising either algorithm, and its sibling arm pins '
            'that a NARROWED list refuses with a message naming both sides — so '
            'the refusal is attributable rather than a silent miss',
      );
      // ⛔ The row is otherwise UNPINNED, and it is the direction the plan
      // already calls the one a bug hides in. With one atSign the configured
      // keyEstablishmentAlgorithms and the published advertisement both belong
      // to it, so a client consulting its own configuration where it should
      // consult the advertisement is invisible in every other row. Nothing in
      // any pack runs two enrollments of one atSign at different algorithm
      // configurations.
    });
  });
}
