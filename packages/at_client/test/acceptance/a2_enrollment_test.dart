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
        'tests/at_functional_test/test/enrollment_pq_key_exchange_live_test.dart',
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
        'tests/at_functional_test/test/enrollment_chain_link_live_test.dart',
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
      //       AtClientPreference.keyEstablishmentAlgorithms = [ml-kem-1024],
      //       where the default is [x-wing], the hybrid.
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
        clauses: ['1568-byte ML-KEM-1024'],
      );
      // The three siblings the paragraph above names. They were described and
      // not cited, so the row's clauses 4, 5 and 6 read as unproven while the
      // tests that prove them sat in the same group.
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'the persisted seed re-derives an ML-KEM package',
        proves: 'restart recoverability — the 64-byte seed is what is filed, '
            'and re-deriving from it reproduces the same kpid, so an address '
            'peers already hold survives a restart',
        clauses: ['re-derives the same kpid'],
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a loaded key keeps its own algorithm whatever the preference says',
        proves: 'the frozen kpid: a preference change does not re-mint an '
            'existing package, because the address is derived from the key '
            'and re-minting would silently strand everything sealed to it',
        clauses: ['an existing key keeps its own algorithm'],
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'an unimplemented algorithm fails rather than minting something else',
        proves: 'the failing-closed arm — the mint throws rather than quietly '
            'substituting the algorithm this build does have, which is the '
            'one outcome an app could not detect',
        clauses: ['an unimplemented algorithm fails the mint'],
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
        clauses: ['`keys[].alg = ml-kem-1024`'],
      );
    });

    test('UC-A2.5 · an enrollment amends its own key package', () {
      // GIVEN alice4 enrolled (E4) advertising a single X-Wing key, with
      //       secrets already sealed to that kpid sitting unread, and a
      //       preference naming BOTH x-wing and ml-kem-1024.
      // WHEN  alice4 starts, and KeyPackageMinting mints the missing ML-KEM
      //       keypair, files it, rebuilds and re-signs the key package with
      //       both keys, and sends enroll:update on its own
      //       APKAM-authenticated connection.
      // THEN  enroll:listns returns the amended package (two keys, suites
      //       covering both KEMs, still derived from the package's own keys);
      //       it still verifies against E4's _apsk, because the update path
      //       relaxes no signature check; a peer negotiates to whichever key
      //       its own keyAlgos order prefers; the pre-existing envelope at the
      //       OLD kpid still opens, because a key that is merely joined by a
      //       second stays active and its private half is retained either way;
      //       nothing already sealed is re-sealed and no conveyance fires, the
      //       updater holding the plaintext already; and an unnamed sibling
      //       metadata key survives the write.
      //
      // ⚠️ Two corrections, both 2026-08-19. The verb is `enroll:update`, not
      // `enroll:updateMetadata` (renamed by decisions 91 ruling 13), and the
      // old wording had the client "mint a second keypair and send" as one
      // explicit act — it is a startup reconciliation against the configured
      // list. The parenthetical also said a replaced kpid is "retained rather
      // than retired"; rulings 95.6-9 say it is retained AND marked retired,
      // so senders stop addressing it while the holder goes on opening what
      // already named it.
      provenIn(
        'tests/at_functional_test/test/key_package_amendment_live_test.dart',
        'UC-A2.5 · an enrollment amends its own key package',
        proves: 'a client configured for both KEMs amends its own record at '
            'startup: enroll:listns returns two keys where the creating '
            'request carried one, the package still verifies against the '
            '_apsk the atServer is serving, the original kpid keeps its '
            'address and stays active, and the suites list widens to cover '
            'both. A DIFFERENTIAL — the control arm is a client whose list '
            'matches what it was created with, which must leave the record '
            'alone, and it is what shows both arms started from one key.',
        clauses: [
          '`keys[]` has two entries',
          'still verifies against E4',
        ],
      );
      provenIn(
        'tests/at_functional_test/test/key_package_amendment_live_test.dart',
        'UC-A2.5 · setting keyPackage leaves a sibling metadata key alone',
        proves: "the second Then — the atServer merges metadata per named "
            'key, so a write naming only keyPackage does not withdraw a '
            'sibling field a later build added. Driven by two enroll:updates '
            'rather than through the client, because the client sends one '
            'named key either way and could not tell a merge from a replace.',
        clauses: ['an unnamed metadata key survives'],
      );

      // ⛔ NOT proven, and deliberately not claimed: the pre-existing envelope
      // at a SUPERSEDED kpid still opening, and a peer negotiating to its own
      // preferred key. Both need a secret sealed before the amendment and read
      // after it. Recorded as plan 14.19 item 36.
    });

    test('UC-A2.6 · only the enrollment itself may amend its metadata', () {
      // GIVEN alice1 (E1, fully privileged) and alice4 (E4, scoped) enrolled.
      // WHEN  E1 sends enroll:update naming E4; and separately a legacy-PKAM /
      //       owner connection (no enrollmentId) sends the same.
      // THEN  both are refused — the second DESPITE carrying full permissions
      //       everywhere else, which is the arm that goes green for the wrong
      //       reason if the self-only check is written as an authorization
      //       lookup rather than an identity test (isAuthorized short-circuits
      //       a connection with no enrollment id to true). The same request
      //       against a REVOKED E4 is refused, so a revoked enrollment cannot
      //       re-advertise an encapsulation target. The accepted arm — E4
      //       updating E4 — runs in the same session, or the two refusals
      //       prove only that the verb refuses everything.
      provenIn(
        'tests/at_functional_test/test/key_package_amendment_live_test.dart',
        'UC-A2.6 · only the enrollment itself may amend its metadata',
        proves: 'both refusals against a live atServer, with the accepted arm '
            'in the same session so they are about WHO asked rather than the '
            'request being malformed. The owner arm is the one that matters: '
            'it carries full permissions everywhere else, and isAuthorized '
            'short-circuits a connection with no enrollment id to true, so it '
            'goes green for the wrong reason if the self-only check is an '
            'authorization lookup rather than an identity test. No mock can '
            'stand in — a fake that accepts everything makes the interlock '
            'and its absence identical.',
        clauses: [
          'both are refused',
          'the arms must differ',
        ],
      );

      // ⛔ NOT proven, and deliberately not claimed: the state gate — the same
      // request against a REVOKED E4. Recorded as plan 14.19 item 36.
    });
  });
}
