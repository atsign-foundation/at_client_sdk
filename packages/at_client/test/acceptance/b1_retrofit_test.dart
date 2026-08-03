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

import 'blockers.dart';

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
      fail('not implemented');
    }, skip: rf2b);

    test('UC-B1.2 · second install on a copied keyfile (alice1c)', () {
      // GIVEN after B1.1; pq_signing_root exists; alice1c is a clone of E1's pre-PQ
      //       keyfile.
      // WHEN  alice1c runs the retrofit.
      // THEN  identical to B1.1 except it REQUESTS rather than creates: it mints
      //       its own PQ APKAM keypair + key package, self-spawns its own
      //       distinct fresh auto-approved enrollment (never a second keypair
      //       under E1), then requests the signing-root private, verifies
      //       public/private correspondence, and stores.
      fail('not implemented');
    }, skip: rf2b);

    test('UC-B1.3 · third client on a different enrollment (alice3, E2)', () {
      // GIVEN after B1.1; alice3 on E2 with its own legacy RSA APKAM;
      //       pq_signing_root exists.
      // WHEN  alice3 runs the retrofit.
      // THEN  identical to B1.2 for the bootstrap. The distinction appears only
      //       for NAMESPACED secrets — a restricted E2 receives only its
      //       authorised subset of nskey keys.
      fail('not implemented');
    }, skip: rf2b);
  });
}
