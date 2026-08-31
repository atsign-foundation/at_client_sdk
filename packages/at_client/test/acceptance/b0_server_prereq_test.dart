/// B0 · Prerequisite — atServer upgrade.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 7.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

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
      provenIn('tests/at_end2end_test/test/pq/legacy_server_abort_test.dart',
          'UC-B0.1: the upgrade aborts cleanly',
          proves: 'all five clauses against a PINNED pre-PQ atServer '
              '(vip-p3.15.0): the upgrade throws AtEnrollmentException naming '
              'the missing auto-approve, the keyfile keeps its RSA APKAM and '
              'gains no typed material, and the server is left with no signing '
              'root and no pending enrollment',
          clauses: ['mints no PQ keys, logs why']);
      provenIn('tests/at_end2end_test/test/pq/legacy_server_abort_test.dart',
          'UC-B0.1: the pre-PQ atServer refuses a second write to an immutable',
          proves: 'the parenthetical, which nothing exercised: on the SAME '
              'pinned pre-PQ image an immutable create lands and a second '
              'write to it is refused by the server, so the interlock is not a '
              'PQ-only verb. The create is read back first, so the refusal '
              'cannot be a record that never landed. Run 2026-08-31 against '
              'vip-p3.15.0. NOTE the limit: the image lacks all four surface '
              'items by construction and the client aborts at the first check '
              'it reaches, so nothing here discriminates WHICH absence caused '
              'the abort',
          clauses: ['mints no PQ keys, logs why']);
      provenIn('tests/at_end2end_test/test/pq/legacy_server_abort_test.dart',
          'UC-B0.1: a scoped parent cannot tidy up',
          proves: 'the limit of the cleanup, asserted rather than hidden: a '
              'parent without __manage cannot deny its own aborted request, '
              'and the refusal says so instead of implying the server is '
              'clean');
    });
  });
}
