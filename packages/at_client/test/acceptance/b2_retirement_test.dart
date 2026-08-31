/// B2 · Legacy retirement & lockout.
///
/// The lockout is the OLD ENROLLMENT'S EXPIRY CAP, never an explicit
/// per-pubkey delete — there is no per-APKAM-key delete under 1:1:1.
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
      //       retrofitted, which capped E1's legacy enrollment; alice1b has not
      //       retrofitted.
      // WHEN  alice1b tries to authenticate (legacy) after the cap elapses.
      // THEN  auth FAILS — the legacy enrollment's expiry cap has elapsed (or it
      //       was explicitly revoked) and alice1b never minted its own PQ
      //       keypair; alice1b must re-enroll.
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_retirement_e2e_test.dart',
        'UC-B2.1/B2.2: the retrofit caps its parent',
        proves:
            'a copy of the pre-PQ keyfile taken before the retrofit, and never '
            'upgraded, is refused with AT0028 "expired or invalid" — the '
            'keypair in it is untouched and still valid, so the lockout is the '
            'enrollment\'s expiry cap and not a per-key delete. The sibling '
            'legacy enrollment that never retrofitted still authenticates in '
            'the same run, so the refusal is attributable to the cap. And the '
            'remedy is asserted rather than left as advice: a fresh OTP '
            'enrollment on the same atSign authenticates moments later, which '
            'is what "must re-enroll" means and what distinguishes a capped '
            'credential from a broken atSign',
        clauses: [
          'never minted its own PQ keypair',
        ],
      );
    });

    test('UC-B2.2 · grace-period variant', () {
      // GIVEN the deployment configured a server-config grace.
      // WHEN  alice1 retrofits, and later a sibling clone of the same pre-PQ
      //       keyfile does.
      // THEN  legacy auth survives until min(now + grace, its own remaining
      //       lifetime), where now is the most recent successor's FIRST
      //       AUTHENTICATION on a connection it opened itself. The cap re-arms
      //       on each one, so the window is not a fixed deadline: each sibling
      //       that upgrades and authenticates extends it by a full grace
      //       period, and a retrofit whose successor never authenticates arms
      //       nothing. Once legacy auth lapses, UC-B2.1 applies. The bypass
      //       being open during the window is an explicit trade-off.
      //
      // ⛔ The trigger is RULED AND NOT YET BUILT. The atServer arms the cap at
      //    submission today and exempts an atSign's first enrollment entirely,
      //    so the citation below carries the formula and the lapse but not the
      //    trigger or the re-arm.
      //
      // ⚠️ This comment said the cap IS the grace window, and that clones may
      //    retrofit until the cap elapses - a fixed deadline set by the first
      //    sibling. That was corrected in the catalogue on 2026-08-27 and here
      //    on 2026-08-31: a fixed deadline would strand every laggard whose
      //    next run fell outside it.
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_retirement_e2e_test.dart',
        'UC-B2.1/B2.2: the retrofit caps its parent',
        proves:
            'the cap IS the configured grace: that atSign\'s atServer runs a '
            'zero-hour apkamSelfEnrollmentGraceHours, and the same test '
            'against the default 720h grace shows the copy authenticating '
            'normally — so the window is what decides, not the retrofit alone',
      );
      provenIn(
        'tests/at_end2end_test/test/pq/retrofit_e2e_test.dart',
        'UC-B1.2: a clone of the same pre-PQ keyfile gets its OWN enrollment',
        proves: 'the other half of the window: while the grace is open (the '
            'default 720h on that atSign) a sibling clone of the same keyfile '
            'still authenticates as the capped parent and retrofits to its own '
            'fresh enrollment',
      );
    });
  });
}
