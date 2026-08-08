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

import 'blockers.dart';
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
      provenIn('tests/at_end2end_test/test/nskey_recipient_not_ready_test.dart',
          'UC-A4.2: a share to a recipient with no namespace key fails, naming ',
          proves: 'an active-PQ alice writing toward a bob who never enabled '
              'the namespace is refused with an exception naming @bob and the '
              'namespace — cross-atSign, against two live atServers, on a '
              'run-unique namespace so the absence is genuine');
      provenIn('tests/at_functional_test/test/nskey_data_path_e2e_test.dart',
          'with the escape hatch opened, the write goes out under legacy',
          proves: 'the explicit opt-in arm: with allowLegacyCryptoFallback set '
              'the same cold-start write proceeds under legacy and the record '
              'is stamped legacy — the downgrade is visible, never silent');
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
              'write goes out stamped legacy and the legacy peer reads it');
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
      // GIVEN alice's app is mid-rollout: alice1 active, alice2 an old
      //       pre-capability build; bob's side holds the namespace key.
      // WHEN  alice1 shares/notifies @bob.
      // THEN  the write takes the nskey data path. alice2 not being able to
      //       read PQ records is the release-ordering discipline violated —
      //       the app developer's failure mode, explicitly not the SDK's to
      //       detect (decisions 36). What the SDK guarantees: alice2's own
      //       legacy writes still work, nothing becomes unreadable to anyone,
      //       and alice2's upgrade is purely additive.
      provenIn('tests/at_end2end_test/test/nskey_cross_atsign_test.dart',
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
      provenIn('tests/at_end2end_test/test/nskey_cross_atsign_test.dart',
          'alice shares with bob, and bob reads it with his own nskey private',
          proves: 'with bob\'s key published, alice\'s write is discovered by '
              'plookup, sealed to bob\'s advertised generation, and bob opens '
              'it with his own private — the post-flip steady state, live');
      provenIn('packages/at_client/test/cold_start_test.dart',
          'says yes once the destination has published a key',
          proves: 'the flip\'s mechanism: the same query that said no answers '
              'yes the moment the key exists, with no state held on alice\'s '
              'side to invalidate');
    });
  });
}
