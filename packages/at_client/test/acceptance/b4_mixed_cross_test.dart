/// B4 · Mixed-PQ across atSigns — the cold-start gate, cross-atSign.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 11 (rewritten 2026-08-05
/// for the app-decides model, `decisions.md` 36). Within a namespace,
/// cross-atSign traffic is between installs of the same app, so "mixed" means
/// the same app at different stages on the two sides — and the SDK's whole
/// contribution is refusing by name when the destination has no key, taking
/// legacy only on explicit opt-in, and never substituting a scheme silently.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('B4 · mixed-PQ across atSigns', () {
    test('UC-B4.1 · active-PQ alice shares toward a bob with no namespace key',
        () {
      // GIVEN alice's install is active; bob's has never run the capability
      //       build, so public:__nskey.<ns>@bob does not exist.
      // WHEN  alice1 shares or notifies @bob:<k>.<ns>@alice.
      // THEN  the write fails cold start BY NAME, unless the app opted into
      //       allowLegacyCryptoFallback — in which case it goes out legacy,
      //       stamped as such on the record. Never a silent downgrade.
      provenIn(
          'tests/at_end2end_test/test/pq/nskey_recipient_not_ready_test.dart',
          'UC-A4.2: a share to a recipient with no namespace key fails, naming ',
          proves: 'an active-PQ alice writing toward a bob who never enabled '
              'the namespace is refused with an exception naming @bob and the '
              'namespace — cross-atSign, against two live atServers, on a '
              'run-unique namespace so the absence is genuine');
      provenIn('tests/at_functional_test/test/nskey_data_path_live_test.dart',
          'with the escape hatch opened, the write goes out under legacy',
          proves: 'the explicit opt-in arm: with allowLegacyCryptoFallback set '
              'the same cold-start write proceeds under legacy and the record '
              'is stamped legacy — the downgrade is visible, never silent');
      provenIn('tests/at_end2end_test/test/pq/pq_cold_start_recovery_test.dart',
          'UC-B4.1: with the fallback opted in, the cold write goes legacy',
          proves: 'the rest of the clause, cross-atSign and in one run: with '
              'the hatch open the cold write goes out stamped legacy and '
              'carries NO ckKid, which is the monolithic model — the '
              'per-value key rides with the value instead of being conveyed '
              'as its own record; and the first write after the recipient\'s '
              'key appears is PQ with no flag to flip, the app having never '
              'touched the preference again and seen no refusal to react to. '
              'Control: a second write taken before the key exists stays '
              'legacy, so the flip is the key appearing. ⚠️ This row is '
              'pinnable only since 2026-08-27, when the clause stopped '
              'requiring "a PQ self-copy for alice\'s own scope" — a record '
              'put does not write, AtCollection being where that lives',
          clauses: ['the *first write after bob\'s key appears* is PQ']);
    });

    test('UC-B4.2 · legacy @alice receives from PQ @bob (the interop question)',
        () {
      // GIVEN @alice legacy (no pq_signing_root, no nskeys); @bob PQ-native.
      // WHEN  bob's app shares with @alice (and a legacy app on @alice shares
      //       with @bob).
      // THEN  interop works BY DEFAULT in both directions, because legacy
      //       material outlives the atSign's own migration (decisions 37):
      //       toward alice via the explicit legacy fallback to her publickey;
      //       toward bob because even a PQ-native onboard publishes
      //       public:publickey by default. Only the opt-out refuses it.
      provenIn('tests/at_functional_test/test/pq_legacy_interop_live_test.dart',
          'UC-B4.2 inbound',
          proves: 'the inbound half: a legacy app on a freshly CRAM-activated '
              'pre-PQ atSign shares with a PQ-native one, and the PQ-native '
              'one opens it with the RSA keypair its activation minted by '
              'default — three live atSigns, all three minted by the test so '
              '"pre-PQ" is asserted rather than borrowed');
      provenIn('tests/at_functional_test/test/pq_legacy_interop_live_test.dart',
          'UC-B4.2 outbound',
          proves: 'the outbound half, in both arms: a post-quantum app on the '
              'PQ-native atSign is REFUSED by name toward a peer with no '
              'namespace key, and with allowLegacyCryptoFallback set the same '
              'write goes out stamped legacy and the legacy peer reads it',
          clauses: [
            'because legacy material outlives the atSign\'s own migration',
          ]);
      provenIn('tests/at_functional_test/test/pq_legacy_interop_live_test.dart',
          'UC-B4.2 opt-out',
          proves: 'the only atSign that refuses is the one that asked to: '
              'activated with mintLegacyMaterial:false it publishes no '
              'publickey, and a legacy peer\'s send fails rather than '
              'producing ciphertext nobody holds a key for');
    });

    test(
        'UC-B4.3 · mid-rollout @alice (one install active, one old) shares '
        'with @bob', () {
      provenIn('packages/at_client/test/legacy_client_refusal_test.dart',
          'a legacy-only install refuses a record stamped at/symmetric/AES/GCM',
          proves: 'the arm nothing established - that a pre-capability install '
              'FAILS to read a PQ-stamped record. Asserted on the exception '
              'type AND its message naming the id, with the same install '
              'reading a legacy-stamped record as the control, so a client '
              'that refused everything could not satisfy it',
          clauses: ['cannot read']);
      // GIVEN alice's app is mid-rollout: alice1 active, alice2 an old
      //       pre-capability build; bob's side holds the namespace key.
      // WHEN  alice1 shares/notifies @bob.
      // THEN  the write takes the nskey data path. alice2 not being able to
      //       read PQ records is the release-ordering discipline violated —
      //       the app developer's failure mode, explicitly not the SDK's to
      //       detect (decisions 36). What the SDK guarantees: alice2's own
      //       legacy writes still work, nothing becomes unreadable to anyone,
      //       and alice2's upgrade is purely additive.
      provenIn('tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
          'alice shares with bob, and bob reads it with his own nskey private',
          proves: 'the active install\'s cross-atSign write takes the nskey '
              'data path against a live pair — the half of the row the SDK '
              'owns');
      provenIn('packages/at_client/test/acceptance/cross_cutting_test.dart',
          'reads are universal',
          proves: 'the additive-upgrade guarantee: a client that gains the PQ '
              'providers still routes every legacy record, so nothing alice2 '
              'wrote or will read is lost by anyone upgrading around it');
    });

    test(
        'UC-B4.4 · bob\'s install reaches capability, alice\'s shares flip '
        'to PQ', () {
      // GIVEN bob's install runs the capability build for the first time and
      //       mints/publishes his namespace key; alice's install is active.
      // WHEN  alice1 next shares/notifies @bob.
      // THEN  alice's next ensureCurrent re-plookup finds the advertisement
      //       and the write goes via the nskey data path — cold start ends for
      //       bob with no action from alice.
      provenIn('tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
          'alice shares with bob, and bob reads it with his own nskey private',
          proves: 'with bob\'s key published, alice\'s write is discovered by '
              'plookup, sealed to bob\'s advertised generation, and bob opens '
              'it with his own private — the post-flip steady state, live');
      provenIn('tests/at_end2end_test/test/pq/pq_cold_start_recovery_test.dart',
          'UC-B4.4: the recipient publishing is the whole trigger',
          proves: 'the clause as written, including the transition itself, '
              'which the steady-state citation above cannot reach. The sender '
              'is REFUSED first, so what follows is about a client that has '
              'already asked and been told no; the recipient then publishes '
              'and the very next write goes out on the nskey data path, with '
              'the CK conveyed as its own record — recipientKind nskey, so '
              'addressed to the namespace rather than a device — carrying the '
              'generation the recipient actually advertised, and with no '
              'sealedKey inline. Control: a key ring that never probed sees '
              'the recipient over the same connection at the same moment, '
              'separating "they published" from "the sender can see it". '
              'Mutation-proven four times, one per assertion',
          clauses: ['the recipient\'s key appearing is the whole trigger']);
      provenIn('tests/at_end2end_test/test/pq/pq_cold_start_recovery_test.dart',
          'UC-B4.1: with the fallback opted in, the cold write goes legacy',
          proves: 'the parenthetical the citation above does not cover — "or '
              'the fallback, if opted-in". An app that opened the escape hatch '
              'never sees a refusal, so nothing tells it the recipient has '
              'arrived and the write simply has to start going out PQ. It '
              'does, on the first write after the key appears, with the '
              'control (a second write taken BEFORE the key exists, which '
              'stays legacy) green — so the flip is the key appearing rather '
              'than the second write. What the fallback already wrote stays '
              'legacy',
          clauses: ['the recipient\'s key appearing is the whole trigger']);
      provenIn('packages/at_client/test/cold_start_test.dart',
          'says yes once the destination has published a key',
          proves: 'that the readiness query answers yes for a destination that '
              'has published. ⚠️ It does NOT observe the flip: its client '
              'never asked before the key existed, so nothing about a '
              'transition is exercised here. This said the flip needed "no '
              'state held on alice\'s side to invalidate", and that sentence '
              'was false when it was written — the resolver remembered the '
              'miss, so a client that HAD asked went on refusing. Fixed '
              '2026-08-27; the transition itself is pinned live by '
              'pq_cold_start_recovery_test.dart, whose first write is the one '
              'that warms the miss');
    });
  });
}
