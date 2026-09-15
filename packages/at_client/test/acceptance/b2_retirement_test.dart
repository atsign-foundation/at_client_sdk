/// B2 · Legacy retirement & lockout.
///
/// The lockout is the SUPERSESSION — the old enrollment revoked at its
/// successor's first authentication — never an explicit per-pubkey delete:
/// there is no per-APKAM-key delete under 1:1:1, and no grace.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 9.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('B2 · legacy retirement & lockout', () {
    test('UC-B2.1 · un-upgraded copy is locked out after retirement', () {
      // GIVEN E1's pre-PQ keyfile was copied to a second host alice1b (against
      //       advice) — the same legacy APKAM keypair on two hosts; alice1
      //       retrofitted, and its successor's first authentication revoked
      //       E1's legacy enrollment as superseded; alice1b has not retrofitted.
      // WHEN  alice1b tries to authenticate (legacy) afterwards.
      // THEN  auth FAILS with AT0027 — the legacy enrollment was revoked as
      //       superseded (or explicitly revoked) and alice1b never minted its
      //       own PQ keypair; alice1b must re-enroll.
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_retirement_e2e_test.dart',
        'UC-B2.1/B2.2: the retrofit revokes its parent at first authentication',
        proves:
            'a copy of the pre-PQ keyfile taken before the retrofit, and never '
            'upgraded, is refused with AT0027 "revoked" — the keypair in it is '
            'untouched and still valid, so the lockout is the supersession and '
            'not a per-key delete. The sibling legacy enrollment that never '
            'retrofitted still authenticates in the same run, so the refusal '
            'is attributable to the supersession. And the remedy is asserted '
            'rather than left as advice: a fresh OTP enrollment on the same '
            'atSign authenticates moments later, which is what "must '
            're-enroll" means and what distinguishes a superseded credential '
            'from a broken atSign',
        clauses: [
          'never minted its own PQ keypair',
        ],
      );
    });

    test('UC-B2.2 · no grace: the window closes at first authentication', () {
      // GIVEN alice1 retrofitted; a sibling clone of the same pre-PQ keyfile
      //       has not.
      // WHEN  alice1's successor first authenticates on a connection it opened
      //       itself, and the clone tries to authenticate or retrofit after.
      // THEN  legacy auth survives exactly until that first authentication and
      //       no longer — no grace window, nothing re-arms; the clone is
      //       refused AT0027 and must re-enroll (UC-B2.1). A root predecessor
      //       is the one exception: supersession never revokes it, so clones
      //       of the atSign's first enrollment's keyfile may each retrofit in
      //       their own time (UC-B1.2).
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_retirement_e2e_test.dart',
        'UC-B2.1/B2.2: the retrofit revokes its parent at first authentication',
        proves:
            'the window closes at once: a copy taken before the retrofit is '
            'refused AT0027 in the same session in which the successor first '
            'authenticated, with no grace configured anywhere — the setting no '
            'longer exists — while a sibling legacy enrollment that never '
            'retrofitted still authenticates',
        clauses: ['there is no grace window and nothing re-arms'],
      );
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_e2e_test.dart',
        'UC-B1.2: a clone of the same pre-PQ keyfile gets its OWN enrollment',
        proves: 'the exception: B1.1\'s predecessor is a ROOT enrollment, so '
            'its successor\'s first authentication leaves it alive, and a '
            'clone of that keyfile still authenticates as it afterwards and '
            'retrofits to its own fresh enrollment',
        clauses: ['A root predecessor is the one exception'],
      );
    });
  });
}
