/// A5 · Rotation & revocation (new world).
///
/// The two levers are distinct and must not be conflated: CK rotation is the
/// cheap O(1) coarse-FS lever; nskey-KEYPAIR rotation is the heavy
/// O(n)-per-enrollment revocation + post-compromise-security lever.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 6.
library;

import 'package:test/test.dart';

import 'blockers.dart';

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
      fail('not implemented');
    }, skip: b2);

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
      fail('not implemented');
    }, skip: b2);

    test('UC-A5.2 · per-enrollment auth revocation', () {
      // GIVEN @alice pq-native; the keyfile holding E2's APKAM keypair is lost.
      // WHEN  the operator runs enroll:revoke on E2.
      // THEN  E2's one APKAM keypair can no longer authenticate; alice1 is
      //       unaffected; E2 gets no new secrets — excluded at BOTH
      //       discovery+push and the requestSecret pull serve.
      fail('not implemented');
    }, skip: b2);

    test('UC-A5.3 · enrollment revocation composes with keypair rotation', () {
      // GIVEN enrollment E2 compromised (it holds exactly one APKAM keypair).
      // WHEN  the operator revokes E2.
      // THEN  E2's APKAM keypair is cut at auth; paired with nskey-keypair
      //       rotation excluding E2 (UC-A5.1b) to deny new-data keys.
      fail('not implemented');
    }, skip: b2);
  });
}
