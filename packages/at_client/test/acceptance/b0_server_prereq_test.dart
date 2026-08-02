/// B0 · Prerequisite — atServer upgrade.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 7.
library;

import 'package:test/test.dart';

import 'blockers.dart';

void main() {
  group('B0 · atServer upgrade prerequisite', () {
    test(
        'UC-B0.1 · a PQ-capable client cannot PQ-upgrade against a legacy '
        'atServer', () {
      // GIVEN aliceS = legacy (no PQ verbs); alice1 is a PQ-capable build.
      // WHEN  alice1 attempts the upgrade sequence.
      // THEN  the new PQ surface (ML-DSA APKAM auth, flattened enroll:listns,
      //       EnrollParams.metadata, authenticated self-retrofit auto-approve)
      //       is unavailable, so alice1 ABORTS CLEANLY, stays legacy, mints no
      //       PQ keys, and logs why. No partial state on the server.
      fail('not implemented');
    }, skip: rfSrv);
  });
}
