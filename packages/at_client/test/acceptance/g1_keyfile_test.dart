import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part G1 — signature agility, the keyfile rows (`acceptance.md` section 16.2).
///
/// The split where an enrollment's APKAM **authentication** key stops being the
/// key it **signs** documents with. These four rows are about the at-rest
/// keyfile: which enrollment a file authenticates as, what a retrofit leaves
/// behind, and what opening a legacy file must not do to it.
///
/// ⚠️ **Every row in this cluster was rewritten on 2026-08-18**, and three of
/// the four were describing code that had been deleted or reversed. They were
/// written 2026-08-11 as a forward specification and the subsystem was rebuilt
/// underneath them on 08-13 and 08-14, while nothing compared the two — the
/// catalogue's regexes hard-coded `UC-[ABC]`, so this cluster was invisible to
/// every check in this directory. Widening that class is what makes these rows
/// real; the rows existing never did.
void main() {
  test('UC-G1.1 · the derivation is offered, not applied', () {
    // GIVEN a keyfile holding exactly one active privateAuthentication
    //       material.
    // WHEN  a caller asks AtKeys.resolveAuthenticatingEnrollment().
    // THEN  it returns that material's enrollment; with two it throws naming
    //       both; with none it returns null.
    // AND   authentication does NOT apply it: a request with no enrollment id
    //       falls back to the flat, stored, deprecated AtKeys.enrollmentId.
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'the authenticating enrollment is null with no typed auth material',
        proves: 'the resolver answers null rather than guessing when a file '
            'holds nothing typed — the arm the no-id default is measured '
            'against');
    provenIn('packages/at_auth/test/at_auth_test.dart',
        'with no enrollment id supplied, the FLAT stored one is used',
        proves: 'the second clause, and the one the row got backwards: the '
            'resolver is not what authentication falls back to. The fixture '
            'is legacy-only, so the resolver returns null while the stored id '
            'is real — which is what makes the assertion discriminate');
  });

  test('UC-G1.2 · a retrofit leaves one active auth key, touching nothing '
      'legacy', () {
    // GIVEN a legacy keyfile that then retrofits.
    // WHEN  the retrofit completes.
    // THEN  the new material is active under the new enrollment id and is the
    //       only active privateAuthentication; the legacy APKAM keypair is
    //       left in the flat fields byte-identical and statusless.
    provenIn('packages/at_auth/test/at_self_enrollment_test.dart',
        'the keyfile after: typed materials under the new id, flat fields',
        proves: 'the flat legacy keypair comes back byte-identical — the row '
            'used to say it was RETIRED, and a test written to that would '
            'have prompted clearing fields the legacy round-trip depends on');
  });

  test('UC-G1.3 · retirement frees the slot', () {
    // GIVEN an active privateAuthentication for enrollment E.
    // WHEN  it is retired and a replacement filed under a new keyId.
    // THEN  addKey accepts it, because the invariants count only active
    //       material. Without the retire, the add throws.
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'retiring a key frees its slot for a replacement',
        proves: 'the substantive claim. The row also said this was "the arm '
            'that throws today", which stopped being true 92 minutes after it '
            'was written');
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'only one enrollment may hold an active authentication key',
        proves: 'the contrast arm, without which the first assertion is '
            'satisfied by invariants that refuse nothing');
  });

  test('UC-G1.4 · opening a legacy keyfile does not upgrade it', () {
    // GIVEN a .atKeys file in the pure legacy shape.
    // WHEN  a new build reads it, changes nothing, and flushes.
    // THEN  the same fields with the same values and no version key — field
    //       for field, not byte for byte, because the emitter has one fixed
    //       order. A version:1 document carrying a top-level keys array is
    //       refused by name rather than read as legacy.
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'a legacy document round-trips field-for-field through a new build',
        proves: 'no upgrade markers are added. This test was named '
            '"byte-identically" until 2026-08-18 while comparing two Maps, '
            'which is why the row claimed a guarantee nothing asserted');
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'an atsign alone does not stamp a legacy file with a version',
        proves: 'the no-version half, with its own positive control');
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'a version 1 document carrying a top-level keys array is refused',
        proves: 'the clause the row had backwards. Both the empty and the '
            'populated array, asserted on the refusal message so an '
            'unrelated validation throw cannot satisfy it');
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'and the same document without it parses',
        proves: 'the control: fromJson does not simply refuse everything');
  });
}
