/// A5 · Rotation & revocation (new world).
///
/// The two levers are distinct and must not be conflated: CK rotation is the
/// cheap O(1) coarse-FS lever; nskey-KEYPAIR rotation is the heavy
/// O(n)-per-enrollment revocation + post-compromise-security lever.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 6.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('A5 · rotation & revocation', () {
    test('UC-A5.1(a) · coarse forward secrecy by rotating the symmetric CK',
        () {
      // GIVEN the app_1.my_apps@alice nskey exists.
      // WHEN  alice1 cuts a new CK, conveys it once sealed to the nskey, points
      //       new writes at it, then DELETES the old CK's at/nskey conveyance
      //       record and every enrollment evicts the cached old CK.
      // THEN  old-CK-era data becomes undecryptable — the nskey private cannot
      //       help, since no sealed copy of the old CK survives. Retaining the
      //       old conveyance instead = history access (the per-namespace FS
      //       retention knob).
      provenIn(
        'tests/at_functional_test/test/content_key_rotation_live_test.dart',
        'deleting the superseded conveyance makes its era undecryptable',
        proves: 'a value written under the first CK reads back (the control '
            'arm), the rotation deletes its conveyance from the atServer, and '
            'the same read then fails with the nskey private untouched — '
            'while a value written under the successor round-trips. The '
            'sibling test in that file holds the retention knob\'s other '
            'position: rotating WITHOUT the delete leaves the era readable, '
            'which is the default.',
      );
    });

    test('UC-A5.1(b) · revocation + PCS by rotating the nskey keypair', () {
      // GIVEN the nskey exists and an enrollment must be excluded.
      // WHEN  alice1 takes the _nskeylock lock, mints the next nskey keypair
      //       EXCLUDING the revoked enrollment, OVERWRITES
      //       public:__nskey.<ns>@alice with the new {nskeyKid, publicKey}, and
      //       pushes the successor private to surviving enrollments via __ssenv.
      // THEN  new CKs seal to the successor nskey and their conveyances carry
      //       the new nskeyKid; survivors retain the prior private so retained
      //       history still opens. A peer notices only at its next
      //       ensureCurrent re-plookup — WITHOUT that the revocation does not
      //       hold, since a peer still sealing to the superseded generation
      //       hands the revoked enrollment a key it can open. A joiner approved
      //       after the rotation gets the current generation and pulls older
      //       ones on demand. Heavy, O(n)-per-enrollment, DISTINCT from CK
      //       rotation.
      provenIn(
        'tests/at_functional_test/test/nskey_rotation_live_test.dart',
        'UC-A5.1(b) · a rotation publishes a successor',
        proves: 'three live enrollments: the rotation overwrites the published '
            'advertisement (read back by an enrollment that did NOT rotate, so '
            'it is the atServer\'s copy and not the rotator\'s memory), pushes '
            'the successor private to the survivor\'s keyfile, drops the '
            'excluded enrollment from the roster the push enumerates (with the '
            'unexcluded control arm), and retains the superseded private so '
            'records sealed to it still open.',
      );
      // The sender-side half — a peer re-plookups and cuts a fresh CK when the
      // advertised nskeyKid changes — is `ensureCurrent`'s rotation check,
      // covered by ck_manager_test.dart's generation tests and exercised live
      // by nskey_cross_atsign_test.dart's rotation case.
    });

    test('UC-A5.2 · per-enrollment auth revocation', () {
      // GIVEN @alice pq-native; the keyfile holding E2's APKAM keypair is lost.
      // WHEN  the operator runs enroll:revoke on E2.
      // THEN  E2's one APKAM keypair can no longer authenticate; alice1 is
      //       unaffected; E2 gets no new secrets — excluded at BOTH
      //       discovery+push and the requestSecret pull serve.
      provenIn(
        'tests/at_functional_test/test/nskey_rotation_live_test.dart',
        'UC-A5.2/A5.3 · a revoked enrollment cannot authenticate',
        proves: 'the revoked enrollment\'s own APKAM keypair authenticates on '
            'a fresh connection before the revoke and is refused after it, '
            'while a sibling enrollment still authenticates; and it disappears '
            'from the enroll:listns roster that both the push and the serve '
            'enumerate. The pull-serve half of "excluded at both" is pinned '
            'deterministically at unit level by the revocation-guard group in '
            'test/pairwise_secret_sharing_test.dart, where a holder refuses a '
            'requester the roster no longer lists and serves the same request '
            'while it is still listed.',
      );
    });

    test('UC-A5.3 · enrollment revocation composes with keypair rotation', () {
      // GIVEN enrollment E2 compromised (it holds exactly one APKAM keypair).
      // WHEN  the operator revokes E2.
      // THEN  E2's APKAM keypair is cut at auth; paired with nskey-keypair
      //       rotation excluding E2 (UC-A5.1b) to deny new-data keys.
      provenIn(
        'tests/at_functional_test/test/nskey_rotation_live_test.dart',
        'UC-A5.3 · revokeEnrollmentAndRotate revokes first',
        proves: 'the composition run against a live atServer by a privileged '
            'operator enrollment: revoke, then rotate every namespace the '
            'target could read, excluding it. The successor is published, the '
            'revoked enrollment does not hold it even after the sweep that '
            'would have carried a pull\'s answer, and the owner retains the '
            'superseded private. The revoke-before-rotate ORDER — which is '
            'what makes the exclusion enforceable rather than advisory — is '
            'asserted directly in test/nskey_rotation_test.dart.',
      );
    });
  });
}
