import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part G1 — signature agility, the `enroll:update` rows
/// (`acceptance.md` section 16.4).
///
/// An approved enrollment amending its own record: rotating its APKAM key
/// without becoming a different enrollment, and being refused everything else.
///
/// **Every row here is the atServer saying no, so every one is proven live.**
/// A mocked `AtLookUp` that accepts whatever it is handed makes a refusal's
/// presence and its absence indistinguishable, and the at_auth unit suite
/// stubs `executeCommand` to succeed — so these guards are invisible there by
/// construction, not by oversight. The proofs live in the functional pack for
/// the reason UC-B4.2 established: it runs against the virtualenv in CI as
/// well as locally, and can drive more than one enrollment of one atSign in a
/// single file.
///
/// ⚠️ **Three of these four rows were rewritten on 2026-08-18.** UC-G1.10
/// claimed a rotation rewrites `_apsk`, which its own *When* forbids; UC-G1.12
/// paired namespaces with an approval state that has no wire field at all; and
/// UC-G1.13 promised two guards where its *Given* can only reach one.
void main() {
  test('UC-G1.10 · rekey keeps the enrollment id', () {
    // GIVEN an approved enrollment authenticated on its own connection.
    // WHEN  it sends enroll:update with a new apkamPublicKey, signingAlgo and
    //       a valid apkamPublicKeySignature.
    // THEN  the record's key is replaced while the id, appName, deviceName,
    //       namespaces and approval state are untouched — and _apsk is NOT
    //       rewritten, because the request names no apsk.
    provenIn('tests/at_functional_test/test/enroll_update_live_test.dart',
        'UC-G1.10 · rekey keeps the enrollment id',
        proves: 'the record read back from the atServer after the rotation. '
            'It asserts the new key actually landed before asserting what '
            'did not move, so a server that accepted the request and did '
            'nothing fails rather than passes');
  });

  test('UC-G1.11 · proof of possession is required', () {
    // GIVEN the same request with apkamPublicKeySignature absent, or signed
    //       by a key other than the one being installed.
    // THEN  the atServer refuses and the record is unchanged. Both arms run,
    //       and the valid arm must succeed or the refusals are measuring a
    //       server that says no to everything.
    provenIn('tests/at_functional_test/test/enroll_update_live_test.dart',
        'UC-G1.11 · proof of possession is required',
        proves: 'all three arms against the live verifier. The wrong-key arm '
            'is signed by the production helper with the wrong private half, '
            'so it is a well-formed proof over the right bytes that the key '
            'being installed did not make — which a presence check would '
            'wave through',
        clauses: [
          'the atServer refuses and the record is unchanged. Both arms run',
        ]);
  });

  test('UC-G1.12 · namespaces stay out of reach', () {
    // GIVEN an enroll:update naming namespaces.
    // THEN  the atServer refuses it by its own named error, and the record is
    //       unchanged.
    // AND   the client cannot name it: the update request carries no field
    //       for namespaces or approval state at all.
    provenIn('tests/at_functional_test/test/enroll_update_live_test.dart',
        'UC-G1.12 · namespaces stay out of reach',
        proves: 'both halves — the built command carries no namespace, and a '
            'raw request that does carry one is refused with the record '
            'unchanged afterwards. The row used to pair this with an approval '
            'state, which has no wire representation to refuse',
        clauses: [
          'the atServer refuses it by its own named error, not by',
        ]);
  });

  test('UC-G1.13 · self-only', () {
    // GIVEN an enroll:update for enrollment E sent on a connection
    //       authenticated as a different enrollment, and separately on one
    //       carrying no enrollment id at all.
    // THEN  each is refused by the self-only check.
    provenIn('tests/at_functional_test/test/enroll_update_live_test.dart',
        'UC-G1.13 · self-only',
        proves: 'two genuine enrollments of one atSign, plus the owner\'s own '
            'connection, plus the control that the same request succeeds on '
            'its own connection — so both refusals are about who asked rather '
            'than about the request being malformed. The row also promised an '
            'approved-only guard its Given can never reach: the self-only '
            'check runs before the target record is fetched',
        clauses: [
          'each is refused, by the self-only check',
        ]);
  });
}
