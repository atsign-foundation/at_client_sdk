import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part G1 — signature agility, the keyfile rows (`acceptance.md` section 16.2).
///
/// The split where an enrollment's APKAM **authentication** key stops being the
/// key it **signs** documents with. These four rows are about the at-rest
/// keyfile: which enrollment a file authenticates as, what a retrofit leaves
/// behind, and what opening a legacy file must not do to it.
void main() {
  test('UC-G1.1 · the keys name the enrollment', () {
    // GIVEN a keyfile.
    // WHEN  AtAuthImpl.authenticate is handed it and asks
    //       AtKeys.enrollmentToAuthenticateAs().
    // THEN  the one enrollment holding active typed material; with none the
    //       flat stored id; with neither primary; with several it throws.
    // AND   primary never reaches the wire.
    // AND   a client built with an AtKeysIo runs as the same answer, and a
    //       disagreeing id passed beside it is shouted about and ignored.
    provenIn('packages/at_client/test/lifecycle/authenticates_as_test.dart',
        'a RETROFITTED keyfile authenticates as the successor, not the flat',
        proves: 'the typed material wins on the one shape where the flat id '
            'and the typed id are both real and differ: a legacy keyfile is '
            'retrofitted for real, authenticated with nothing passed, and '
            'the id that reached the PKAM is the successor',
        clauses: ['the one enrollment holding active typed']);
    provenIn('packages/at_client/test/lifecycle/authenticates_as_test.dart',
        'a legacy keyfile authenticates as its flat stored enrollment',
        proves: 'with no typed material the flat stored id is what reaches '
            'pkam — asserted after checking the resolver has nothing to offer '
            'on this fixture',
        clauses: ['with none, as the flat stored']);
    provenIn('packages/at_client/test/lifecycle/authenticates_as_test.dart',
        'an ancient keyfile with no enrollment id authenticates as primary',
        proves: 'a keyfile holding neither reaches pkam as primary',
        clauses: ['with neither, as `primary`']);
    provenIn('packages/at_auth/test/plural_enrollments_test.dart',
        'the enrollment to authenticate as is refused rather than picked from',
        proves: 'two live enrollments throw, and the message names both',
        clauses: ['with several it throws naming them all']);
    provenIn('packages/at_commons/test/pkam_verb_builder_test.dart',
        'the atSign\'s own credential authenticates with no enrollment id on',
        proves: 'the bare pkam: is pinned as a raw literal for primary, with '
            'and without the algorithm fields',
        clauses: ['`PkamVerbBuilder` omits it']);
    provenIn(
        'packages/at_client/test/at_client_create_derives_enrollment_test.dart',
        'a disagreeing id is ignored and the keys win',
        proves: 'AtClientImpl.create runs and files the client under the '
            'enrollment its keys authenticate as, not the one the caller '
            'named',
        clauses: ['logged at shout level and']);
  });

  test(
      'UC-G1.2 · a retrofit leaves one active auth key, touching nothing '
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
            'have prompted clearing fields the legacy round-trip depends on. '
            'It now also asserts the resolver names the NEW enrollment, so '
            'the document\'s two answers are both pinned: the flat field '
            'still says legacy because that enrollment goes on '
            'authenticating, while the only ACTIVE privateAuthentication is '
            'the new one. Mutation-proven — pointing the resolver at retired '
            'material reddens it, quoting this assertion',
        clauses: ['and UC-G1.1\'s resolver returns the new enrollment id']);
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
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'a retired key does not free its keyId for reuse',
        proves: 'that the id check is status-blind while the slot check is '
            'not: after retiring, a replacement under the SAME keyId is still '
            'refused, and the same add under a new id is accepted as the '
            'control. Mutation-proven — making the id check skip retired '
            'material reddens it, quoting this assertion. Without it '
            '"retirement frees the slot" reads as though it freed the '
            'identifier too',
        clauses: [
          'A replacement re-using the retired key\'s keyId is still '
              'refused — that check is status-blind'
        ]);
  });

  test('UC-G1.4 · opening a legacy keyfile does not upgrade it', () {
    // GIVEN a .atKeys file in the pure legacy shape.
    // WHEN  a new build reads it, changes nothing, and flushes.
    // THEN  the same fields with the same values and no version key — field
    //       for field, not byte for byte, because the emitter has one fixed
    //       order. A version:1 document carrying a POPULATED top-level keys
    //       array is refused by name rather than read as legacy; an EMPTY one
    //       is accepted, because that is the only shape any released build
    //       wrote and refusing it stranded every keyfile they produced.
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'a legacy document round-trips field-for-field through a new build',
        proves: 'no upgrade markers are added. This test was named '
            '"byte-identically" until 2026-08-18 while comparing two Maps, '
            'which is why the row claimed a guarantee nothing asserted',
        clauses: [
          'the re-emitted document holds the same fields with the same values',
        ]);
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'an atsign alone does not stamp a legacy file with a version',
        proves: 'the no-version half, with its own positive control');
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'a version 1 document carrying a POPULATED keys array is refused',
        proves: 'the refusal half, asserted on the refusal message so an '
            'unrelated validation throw cannot satisfy it');
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'an EMPTY keys array is accepted, because that is what shipped',
        proves: 'the other half, which this row asserted backwards until '
            '2026-08-22. A keyfile CRAM-onboarded with the published at_auth '
            'that introduced `keys` carries it EMPTY - that build never '
            'populated the array - so refusing the empty shape refused every '
            'keyfile a release had written. Measured against a real one');
    provenIn('packages/at_auth/test/at_keys_test.dart',
        'and the same document without it parses',
        proves: 'the control: fromJson does not simply refuse everything');
  });
}
