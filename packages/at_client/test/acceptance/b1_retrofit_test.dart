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
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_e2e_test.dart',
        'UC-B1.1: a privileged retrofit mints the signing root in-flow',
        proves:
            'the retrofit publishes public:pq_signing_root in-flow (nothing in '
            'the test calls mintIfAbsent), files the matching private in the '
            'same keyfile, and anchors the new enrollment — verified as '
            'ChainVerdict.anchored against the published record',
      );
      provenIn(
        'tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart',
        'the full retrofit: no-OTP submit auto-approves, the keyfile holds',
        proves:
            'the submit half: auto-approved with no OTP, a NEW enrollment id, '
            'the keyfile carrying both enrollments, and immediate ML-DSA PKAM '
            'under the new id (record-authoritative, so an RSA signature would '
            'be refused)',
      );
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_retirement_e2e_test.dart',
        'UC-B2.1/B2.2: the retrofit caps its parent',
        proves:
            'the legacy enrollment is capped and ages out rather than being '
            'deleted by key — the THEN clause this row shares with B2',
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
      );
    });
  });
}
