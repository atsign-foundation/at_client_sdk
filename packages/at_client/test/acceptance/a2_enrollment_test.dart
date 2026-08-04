/// A2 · Enrollments (a new enrollment joins).
///
/// Start state: @alice pq-native; pq_signing_root published; alice1 (E1) online.
/// Catalogue: `docs/projects/pq/acceptance.md` section 3.
library;

import 'package:test/test.dart';

import 'blockers.dart';
import 'proven_elsewhere.dart';

void main() {
  group('A2 · enrollments', () {
    test('UC-A2.1 · new enrollment approved by an online enrollment', () {
      // GIVEN @alice pq-native; pq_signing_root published; alice1 (E1) online.
      // WHEN  alice2 requests enrollment E2 for [app_1.my_apps]; alice1 approves.
      // THEN  nothing in the conveyance path is RSA-wrapped (apkamSymmetricKey
      //       rides X-Wing); alice2 holds the app_1 nskey private
      //       but NOT app_2's; alice2 authenticates PQ and decrypts @alice's
      //       app_1.my_apps self data; an app_2 key request is refused; E2's
      //       APKAM key is a distinct, individually-revocable record.
          provenIn(
        'tests/at_functional_test/test/enrollment_pq_key_exchange_e2e_test.dart',
        'a pq enrollment reaches the atServer with no RSA-wrapped key',
        proves: 'the enrol request carries no RSA-wrapped apkamSymmetricKey, and the companion test has the approver mint it and the enrollee recover it',
      );
});

    test('UC-A2.2 · second host using the same (copied) keyfile', () {
      // GIVEN @alice pq-native; alice1 on E1; a second host runs against a copy
      //       of E1's keyfile (alice1b).
      // WHEN  the copy first runs.
      // THEN  the copy SHARES E1's one APKAM keypair and key package — the two
      //       hosts are the same enrollment, one recipient. Secrets already
      //       sealed to that key package open on both, and both hosts share the
      //       signing-root private and E1's namespace authorisations. Revocation
      //       is per-enrollment, so revoking E1 cuts every host sharing the copy.
      fail('not implemented');
    }, skip: owedFunctional);

    test('UC-A2.3 · namespace-restricted enrollment', () {
      // GIVEN alice1 (E1, *) approves alice3 for app_1.my_apps only (E3).
      // WHEN  alice3 enrolls.
      // THEN  alice3, being namespace-scoped rather than fully privileged, does
      //       NOT get the signing-root private, and by approval-time push gets
      //       only the app_1.my_apps nskey private; app_2's is never
      //       delivered. The boundary is enforced at the atServer __ssenv
      //       namespace-delivery gate, not by a client-side refusal alone, so
      //       alice3 can read/write app_1.my_apps but not app_2.my_apps.
      fail('not implemented');
    }, skip: owedFunctional);
  });
}
