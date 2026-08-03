/// B2 · Legacy retirement & lockout.
///
/// The lockout is the OLD ENROLLMENT'S EXPIRY CAP, never an explicit
/// per-pubkey delete — there is no per-APKAM-key delete under 1:1:1.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 9.
library;

import 'package:test/test.dart';

import 'blockers.dart';

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
      fail('not implemented');
    }, skip: rfSrv);

    test('UC-B2.2 · grace-period variant', () {
      // GIVEN the deployment configured a server-config grace; the cap IS the
      //       grace window.
      // WHEN  alice1 retrofits.
      // THEN  legacy auth survives until min(now + grace, expiry); sibling
      //       clones may still retrofit (each to its own fresh enrollment) until
      //       the cap elapses; after the cap, UC-B2.1 applies. The bypass being
      //       open during the window is an explicit trade-off.
      fail('not implemented');
    }, skip: rfSrv);
  });
}
