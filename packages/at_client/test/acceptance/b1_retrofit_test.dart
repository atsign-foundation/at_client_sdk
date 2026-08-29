/// B1 · Upgrade an existing (pre-PQ) atSign — the retrofit scenarios.
///
/// Retrofit is NOT a mutation of the existing enrollment. The authenticated
/// pre-PQ client submits enroll:request with a NEW enrollmentId on its
/// already-authenticated connection (no OTP); the server validates the
/// namespace subset, auto-approves, copies the old expiry, and CAPS the old
/// enrollment without removing it.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 8.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('B1 · retrofit an existing atSign', () {
    test('UC-B1.1 · first client retrofit (alice1)', () {
      // GIVEN @alice legacy (RSA publickey, RSA APKAM per enrollment);
      //       aliceS = pq; pq_signing_root absent.
      // WHEN  alice1 runs the retrofit.
      // THEN  alice1.APKAM = pq on the fresh auto-approved enrollment and PQ
      //       auth works; public:pq_signing_root@alice is created and alice1 serves
      //       its private on request; the legacy enrollment is CAPPED to
      //       min(now + grace, expiry) and ages out — not deleted-by-key; the
      //       legacy encryption key is retained so history stays readable. No
      //       re-onboarding.
      provenIn('tests/at_end2end_test/test/pq/retrofit_e2e_test.dart',
          'UC-B1.1: a privileged retrofit mints the signing root in-flow',
          proves:
              'the retrofit publishes public:pq_signing_root in-flow (nothing in '
              'the test calls mintIfAbsent), files the matching private in the '
              'same keyfile, and anchors the new enrollment — verified as '
              'ChainVerdict.anchored against the published record',
          clauses: [
            'serves the private to other fully privileged enrollments on '
                'request',
          ]);
      provenIn(
          'tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart',
          'the full retrofit: no-OTP submit auto-approves, the keyfile holds',
          proves:
              'the submit half: auto-approved with no OTP, a NEW enrollment id, '
              'the keyfile carrying both enrollments, and immediate ML-DSA PKAM '
              'under the new id (record-authoritative, so an RSA signature would '
              'be refused)',
          clauses: [
            'on the fresh auto-approved enrollment; PQ auth works',
          ]);
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_retirement_e2e_test.dart',
        'UC-B2.1/B2.2: the retrofit caps its parent',
        proves:
            'the legacy enrollment is capped and ages out rather than being '
            'deleted by key — the THEN clause this row shares with B2. It runs '
            'on an atSign configured with a ZERO-hour grace, which is what '
            'makes the ageing-out observable inside a test and also what stops '
            'it saying anything about the VALUE: at zero grace the min always '
            'takes `now`, so an atServer that set the expiry unconditionally '
            'would satisfy every assertion in it. The row beside this one '
            'carries that half',
      );
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_cap_value_e2e_test.dart',
        'UC-B1.1: the cap is min(now + grace, the enrollment\'s own remaining '
            'lifetime)',
        proves: 'the cap as a VALUE, at the deployment\'s ordinary grace, with '
            'three parents whose lifetimes straddle it — and every comparison '
            'is between two values the ATSERVER produced, never against this '
            'process\'s clock, which would be measuring clock agreement '
            'between two machines. A parent expiring in an hour keeps its own '
            'expiry (the grace is the larger candidate, so the min takes the '
            'lifetime); a parent expiring in 2000 hours is pulled in by more '
            'than a day (the grace is the smaller); and a parent with NO '
            'expiry gains one, which is the case a cap that merely shortened '
            'an existing lifetime would leave untouched. The two dated arms '
            'cannot both be satisfied by one behaviour — one tolerates under '
            '30 seconds of movement and the other demands more than a day — '
            'and the record\'s version is asserted to have moved, so '
            '"unchanged" cannot be an enrollment the retrofit never reached. '
            'The control is the two un-retrofitted siblings, still at version '
            '1: the cap lands on the enrollment its own child came from and '
            'nowhere else, which is also what makes it safe on a shared '
            'atSign',
        clauses: [
          'min(now + grace, its own remaining lifetime)',
        ],
      );
      provenIn(
        'tests/at_functional_test/test/pq_advance_ladder_test.dart',
        'one enrollment walks legacy to pqReady to pqActive, and nothing ',
        proves: 'that the legacy ENCRYPTION key survives the advance, which '
            'is what keeps already-written history readable: the ladder walks '
            'one enrollment through every rung and re-reads what was written '
            'at each earlier rung afterwards. A build that retired the '
            'encryption key alongside the signing key would pass every '
            'write-side assertion and fail only here',
        clauses: [
          'Legacy *encryption* key retained (history still '
              'readable)'
        ],
      );
    });

    test('UC-B1.2 · second install on a copied keyfile (alice1c)', () {
      // GIVEN after B1.1; pq_signing_root exists; alice1c is a clone of E1's pre-PQ
      //       keyfile.
      // WHEN  alice1c runs the retrofit.
      // THEN  identical to B1.1 except it REQUESTS rather than creates: it mints
      //       its own PQ APKAM keypair + key package, self-spawns its own
      //       distinct fresh auto-approved enrollment (never a second keypair
      //       under E1), then requests the signing-root private, verifies
      //       public/private correspondence, and stores.
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_e2e_test.dart',
        'UC-B1.2: a clone of the same pre-PQ keyfile gets its OWN enrollment',
        proves:
            'two clones of one pre-PQ keyfile reach DISTINCT enrollment ids '
            'under the same (appName, deviceName); the clone mints no second '
            'root and leaves the published one byte-identical; and it acquires '
            'the private by asking the namespace, which files it into the '
            'keyfile only after checking it corresponds to the published root',
      );
    });

    test('UC-B1.3 · third client on a different enrollment (alice3, E2)', () {
      // GIVEN after B1.1; alice3 on E2 with its own legacy RSA APKAM;
      //       pq_signing_root exists.
      // WHEN  alice3 runs the retrofit.
      // THEN  identical to B1.2 for the bootstrap. The distinction appears only
      //       for NAMESPACED secrets — a restricted E2 receives only its
      //       authorised subset of nskey keys.
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_e2e_test.dart',
        'UC-B1.3: a scoped enrollment retrofits without touching the signing',
        proves: 'a scoped parent cannot escalate to * and __manage on the way '
            'through; its retrofit succeeds and upgrades to ML-DSA; and the '
            'root is untouched — no private held, the pull declines, and no '
            'root link is published. Read off the server enrollment record, '
            'against B1.1\'s privileged arm asserted the same way',
        clauses: ['a scoped E2 does not request the root at all'],
      );

      // The reason the decline gives, which the return value cannot carry:
      // 0 is equally what an enrollment already holding the root returns and
      // what one with no enrollment id returns, so an operator asking why a
      // device never obtained it has only the log to tell the three apart.
      provenIn(
        'packages/at_client/test/pq_signing_root_test.dart',
        'a restricted enrollment says why it is not asking',
        proves: 'the decline names entitlement rather than declining '
            'silently, with the privileged arm of the same method as a '
            'control so an unbound recorder is reported as unbound instead of '
            'passing by matching nothing. Its sibling "a restricted '
            'enrollment asks nobody" carries the no-broadcast half, against a '
            'privileged arm that asks two key packages',
        clauses: ['logging that it is not entitled to hold it'],
      );

      // The namespaced half of the row, and it is a different guarantee from
      // the root: the root is withheld from a scoped enrollment entirely,
      // while nskey privates are FILTERED to what it was granted. Cited at
      // both layers deliberately — the sender is asserted not to send across
      // the boundary, and the atServer is asserted to hold it anyway.
      provenIn(
        'packages/at_client/test/secret_sharing_approver_test.dart',
        'only secrets whose namespace the recipient enrollment is',
        proves: 'the sender-side filter, as a real differential: the approver '
            'holds secrets in two namespaces and the recipient is granted '
            'one, so exactly one envelope is written and it is the granted '
            'namespace\'s. The sibling "without a namespace filter, all '
            'secrets are shared" returns 2, which is what proves the approver '
            'had something to withhold rather than only one secret to begin '
            'with',
        clauses: [
          'a restricted E2 receives only its authorised subset of `nskey` keys'
        ],
      );
      provenIn(
        'tests/at_functional_test/test/enrollment_namespace_gate_test.dart',
        'a scoped enrollment cannot read the envelope channel of a namespace',
        proves: 'the same boundary held by the atServer rather than by the '
            'sender, which is what makes it a gate: the scoped enrollment is '
            'refused an __ssenv record in an ungranted namespace while '
            'reading the granted one on the same connection, and the approver '
            'reads both — so the refusal is a gate rather than an absent '
            'record',
      );
    });

    test('UC-B1.4 · a retrofitted scoped enrollment runs an authenticated verb',
        () {
      // GIVEN a namespace-scoped OTP enrollment holding an RSA-2048 APKAM
      //       keypair - what the OTP path mints, since the request carries no
      //       algorithm to ask with.
      // WHEN  a client is built for it under a posture requiring mldsa65, so it
      //       retrofits itself before its constructor returns.
      // THEN  it runs as a DIFFERENT enrollment id, resolving mldsa65 from that
      //       enrollment's typed material, and an authenticated verb over its
      //       own connection answers.
      //
      // The row exists because B1.1's "PQ auth works" was true in the field
      // while the enrollment could not run a verb: at_auth authenticates on its
      // own connection, before the client exists, and every verb afterwards
      // runs over a different one. Both retrofit ROUTES are cited, because the
      // property is per-route and was proven for one while false for the other.
      provenIn('tests/at_functional_test/test/pq_retrofitted_scope_test.dart',
          'UC-B1.4 · a retrofitted scoped enrollment runs an authenticated verb',
          proves:
              'the STARTUP route - the one at_activate and every SDK consumer '
              'take. The client leaves its enrolled id during construction, '
              'resolves mldsa65 from key material, and answers an authenticated '
              'verb; the id inequality is asserted first, so a run in which no '
              'retrofit happened fails rather than measuring an ordinary '
              'enrollment',
          clauses: [
            'an authenticated verb over its own connection',
            'from that enrollment\'s typed key material',
          ]);
      provenIn(
        'tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart',
        'selfRetrofit switches to a working client: verb connection, monitor,',
        proves:
            'the EXPLICIT route: a selfRetrofit client runs an authenticated '
            'scan, receives over a monitor whose own socket PKAMed '
            'independently, and signs an envelope that verifies against the '
            '_apsk the atServer serves for its enrollment',
      );
      provenIn(
        'tests/at_onboarding_cli_functional_tests/test/pq_native_enroll_test.dart',
        'a legacy enrolment that retrofits at start can still run a verb',
        proves:
            'the same property through the shipped binary: at_activate list on '
            'a keyfile a real retrofit has moved. The keyfile is read on both '
            'sides, so a run in which no retrofit happened fails; with the '
            'defect restored this arm reports exit 1 and at_chops\' refusal',
      );
    });

    test('UC-B1.5 · it reads and writes inside its authorised namespace', () {
      // GIVEN UC-B1.4's retrofitted, scoped client.
      // WHEN  it writes a key in its granted namespace and reads it back.
      // THEN  both succeed - the value is encrypted with the atSign-wide self
      //       key, which is not per-enrollment, so the retrofit strands
      //       nothing.
      provenIn(
        'tests/at_functional_test/test/pq_retrofitted_scope_test.dart',
        'UC-B1.5 · it reads and writes inside its authorised namespace',
        proves: 'put and get under the retrofitted enrollment, against a live '
            'atServer. The client-side authorisation gate reads the enrollment '
            'record the atServer holds for the id this client RUNS as, so a '
            'retrofit that lost its grants fails the write',
      );
      provenIn(
        'tests/at_functional_test/test/pq_advance_ladder_test.dart',
        'one enrollment walks legacy to pqReady to pqActive, and nothing ',
        proves: 'the encryption side of the same walk: a value written at a '
            'legacy rung is encrypted under the atSign-wide self key and '
            'stays readable after the advance. The row\'s other citation '
            'covers only the authorised-namespace half, so this is the arm '
            'that would otherwise rest on nothing',
        clauses: ['The value is encrypted with the atSign-wide self key'],
      );
    });

    test('UC-B1.6 · it is refused outside it', () {
      // GIVEN UC-B1.4's retrofitted, scoped client.
      // WHEN  it writes a key in a namespace it was never granted.
      // THEN  refused, naming insufficient privilege - with the same write one
      //       namespace over succeeding in the same arm.
      //
      // An escalation is silent where a loss is loud: a retrofit that dropped a
      // grant fails the next thing the app does, one that widened them fails
      // nothing at all.
      provenIn('tests/at_functional_test/test/pq_retrofitted_scope_test.dart',
          'UC-B1.6 · it is refused outside its authorised namespace',
          proves:
              'the refusal AND its control in one arm - the same client, the '
              'same operation, one namespace over. Granting the second namespace '
              'as a mutation turns the refusal into a successful write, so the '
              'arm measures the grant boundary rather than the client\'s ability '
              'to write at all. ⚠️ It is the CLIENT-side refusal, and only that: '
              'the message it matches, "insufficient privilege", is raised in '
              'at_client\'s own local_secondary.dart, so this arm would stay '
              'green with the atServer\'s gate removed entirely and any client '
              'not going through at_client would sail past. The atServer half - '
              'AT0009, "not authorized to <verb> key", per verb - is asserted '
              'live under UC-A2.3 in enrollment_namespace_gate_test.dart. '
              'Neither layer alone is the guarantee',
          clauses: [
            'refused, naming insufficient privilege',
          ]);
    });

    test('UC-B1.7 · it holds the parent enrollment\'s grants, verbatim', () {
      // GIVEN UC-B1.4's retrofitted client and the parent it left behind.
      // WHEN  both records are read off the atServer.
      // THEN  the child's namespace map equals the parent's and equals the
      //       literal grant enrolled; and enroll:list from the child returns
      //       its own record alone, because a scoped enrollment holds no
      //       __manage.
      //
      // Verbatim carry-over is a property of the STARTUP route only:
      // _settleEnrollmentIdentity reads the grants off the record, while
      // selfRetrofit takes them as a caller-supplied parameter and reads no
      // record at all.
      provenIn('tests/at_functional_test/test/pq_retrofitted_scope_test.dart',
          'UC-B1.7 · its grants are the parent enrollment',
          proves:
              'both records read off the atServer rather than off the request '
              'the client sent - what was asked for and what was recorded are '
              'different facts. The literal grant is asserted beside the '
              'comparison, so a retrofit that emptied both maps goes red rather '
              'than satisfying the equality',
          clauses: [
            'and equals the literal grant that was enrolled',
            'returns its own record and nothing else',
          ]);
    });
  });
}
