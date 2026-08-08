/// A2 · Enrollments (a new enrollment joins).
///
/// Start state: @alice pq-native; pq_signing_root published; alice1 (E1) online.
/// Catalogue: `docs/projects/pq/acceptance.md` section 3.
library;

import 'package:test/test.dart';

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
        proves:
            'the enrol request carries no RSA-wrapped apkamSymmetricKey, and the companion test has the approver mint it and the enrollee recover it',
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
      provenIn(
        'tests/at_functional_test/test/copied_keyfile_test.dart',
        'a copied keyfile is the same enrollment and the same recipient',
        proves: 'a keyfile round-tripped through its serialized form — which '
            'is what copying it does — resolves to the same key package id, '
            'that id is the one the enrollment advertised, and the copy '
            'authenticates against the live atServer as the same enrollment '
            'id. One enrollment and one recipient, so there is a single thing '
            'to revoke and an operator cannot miss the second host',
      );
    });

    test('UC-A2.3 · namespace-restricted enrollment', () {
      // GIVEN alice1 (E1, *) approves alice3 for app_1.my_apps only (E3).
      // WHEN  alice3 enrolls.
      // THEN  alice3, being namespace-scoped rather than fully privileged, does
      //       NOT get the signing-root private, and by approval-time push gets
      //       only the app_1.my_apps nskey private; app_2's is never
      //       delivered. The boundary is enforced at the atServer __ssenv
      //       namespace-delivery gate, not by a client-side refusal alone, so
      //       alice3 can read/write app_1.my_apps but not app_2.my_apps.
      //
      // Three claims, three proofs, and they are deliberately at different
      // layers: the boundary is asserted to hold at the atServer, *and* the
      // sender is asserted not to send across it. Either alone would be a
      // weaker guarantee than the row states.
      provenIn(
        'tests/at_functional_test/test/enrollment_namespace_gate_test.dart',
        'a scoped enrollment cannot read the envelope channel of a namespace',
        proves: 'the atServer refuses the scoped enrollment\'s llookup of an '
            '__ssenv record in an ungranted namespace, naming the enrollment '
            'and the key, while the same enrollment reads the granted '
            'namespace on the same connection and the approver reads both — '
            'so the refusal is a gate rather than an absent record',
      );
      provenIn(
        'tests/at_functional_test/test/enrollment_chain_link_e2e_test.dart',
        'the root private reaches a privileged enrollment and no other',
        proves: 'the signing-root private is conveyed to a fully privileged '
            'enrollment and withheld from a scoped one, with the grant '
            'asserted to have actually differed between the two arms',
      );
      provenIn(
        'packages/at_client/test/secret_sharing_approver_test.dart',
        'shares namespace-authorized secrets with the approved enrollment',
        proves: 'the sender-side half — shareAllSecretsWith forwards only the '
            'secrets the approved namespaces authorize, so a private for an '
            'ungranted namespace is never put on the wire in the first place',
      );
    });

    test('UC-A2.4 · the key package advertises the configured KEM', () {
      // GIVEN the deployment running alice4 sets
      //       AtClientPreference.keyEstablishmentAlgo = ml-kem-1024, where the
      //       default is the X-Wing hybrid.
      // WHEN  alice4 requests an enrollment, minting the key package that rides
      //       enroll:request.
      // THEN  the advertised key is a 1568-byte ML-KEM-1024 encapsulation key
      //       rather than a 1216-byte X-Wing one — the arms differ in SHAPE,
      //       not only in a label — keys[].alg names ml-kem-1024 and suites
      //       claims ml-kem-1024-rfc9180-v1 alone, so the package never claims
      //       a construction its own key cannot decapsulate. The private is
      //       filed as its 64-byte SEED with the algorithm alongside and
      //       re-derives the same kpid after a restart; filing the 3168-byte
      //       expanded decapsulation key would leave the enrollment unopenable
      //       at the next start, with no error when the mistake is made. A key
      //       that already exists keeps its own algorithm whatever the
      //       preference later says, because the kpid is the address peers seal
      //       to and metadata.keyPackage is never rewritten. An algorithm this
      //       build does not implement fails the mint rather than quietly
      //       minting the other one.
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a client configured for ML-KEM-1024 mints and advertises it',
        proves: 'the mint under the preference, asserted on the key LENGTH '
            '(1568 against the hybrid\'s 1216) as well as the declared alg, so '
            'the two arms cannot pass by agreeing on a label alone. Its '
            'siblings in the same group carry the rest of the row: "the '
            'persisted seed re-derives an ML-KEM package" (restart '
            'recoverability), "a loaded key keeps its own algorithm whatever '
            'the preference says" (the frozen kpid), and "an unimplemented '
            'algorithm fails rather than minting something else".',
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'what gets written declares what the advertised keys can open',
        proves: 'the suites list is DERIVED from the package\'s own keys, not '
            'stated from what this build supports — the distinction that '
            'stops a package advertising one KEM from claiming it can open '
            'constructions built on the other. "a package advertising no key '
            'claims no suite" and "an unrecognised key algorithm contributes '
            'no suite" hold the failing-closed direction.',
      );
    });
  });
}
