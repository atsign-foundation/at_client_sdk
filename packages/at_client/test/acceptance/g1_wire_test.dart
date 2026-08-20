import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part G1 — signature agility, the wire rows (`acceptance.md` section 16.3).
///
/// What a published `_apsk` looks like, what a verifier does with it, and what
/// happens to an envelope whose shape predates the current one. These are the
/// rows a peer's build depends on: the keyfile rows are one machine's business,
/// but every one of these is a promise to somebody else's client.
///
/// ⚠️ **Two of these rows asserted the opposite of the code until 2026-08-18.**
/// UC-G1.5 said the current build never emits the bare `_apsk` string — it
/// emits it deliberately, and ruling 98.1 requires it. UC-G1.6 said an
/// unversioned envelope still verifies — the tree pins its exact opposite as
/// an accepted break. Both were written before ruling 95 collapsed the
/// envelope to one shape.
void main() {
  test('UC-G1.5 · a bare-string _apsk still verifies', () {
    // GIVEN an _apsk published by at_client 3.13.0 — a bare public-key string.
    // WHEN  a current build verifies an envelope from that enrollment.
    // THEN  it succeeds, reading the record as a single active rsa2048 entry.
    // AND   the writer still emits that shape: a lone active rsa2048 key is
    //       spelled bare, and only a second key or another algorithm forces
    //       the array.
    provenIn('packages/at_client/test/apsk_formats_test.dart',
        'a bare RSA _apsk verifies an RSA envelope',
        proves: 'the reader half, end to end against a real signature');
    provenIn('packages/at_client/test/apsk_formats_test.dart',
        'a bare value reads as exactly ONE active rsa2048 entry',
        proves: 'the "single entry" clause, which nothing asserted: a reader '
            'producing two, or one marked retired, would satisfy the verbatim '
            'test while changing what a verifier selects on');
    provenIn('packages/at_client/test/apsk_formats_test.dart',
        'one active rsa2048 key is spelled bare, not as the array',
        proves: 'the writer arm, in the direction the row had inverted');
    provenIn('packages/at_client/test/apsk_formats_test.dart',
        'a second key forces the array',
        proves: 'the control, without which the writer arm is satisfied by a '
            'composer that can only ever emit one form');
  });

  test(
      'UC-G1.6 · an unversioned envelope is refused, and the refusal names '
      'why', () {
    // GIVEN (a) the released 3.14.0 flat envelope — a bare signature sibling
    //       of the payload, no v — and (b) a current-shape envelope whose
    //       protected header omits v.
    // WHEN  a current build reads (a) and verifies (b).
    // THEN  (a) is refused at parse and (b) at verify, naming the version.
    //       There is deliberately no tolerant reading.
    provenIn(
        'packages/at_client/test/released_envelope_incompatibility_test.dart',
        'a released envelope is refused, naming the payload',
        proves: 'arm (a): the released flat shape never parses, so it cannot '
            'reach a verifier at all');
    provenIn('packages/at_client/test/jws_envelope_test.dart',
        'a protected header with NO version is refused, naming the absence',
        proves: 'arm (b), which nothing covered: the same absence arriving in '
            'a shape that DOES parse. It asserts the message names "null" '
            'specifically, so a reader that learned to default a missing '
            'version to 1 would not satisfy it, and it checks the fixture '
            'really omitted the field before asserting the refusal');
  });

  test('UC-G1.7 · the verifier takes the strongest and does not fall back', () {
    // GIVEN an envelope carrying a valid rsa2048 and a CORRUPTED mldsa65
    //       signature, against an _apsk advertising both.
    // WHEN  a build that implements ML-DSA verifies it.
    // THEN  it refuses. The strongest shared algorithm is chosen and its
    //       failure is final — falling back to the valid weaker signature
    //       would let an attacker downgrade by corrupting one entry.
    provenIn('packages/at_client/test/jws_envelope_test.dart',
        'a valid RSA signature does NOT rescue a corrupt ML-DSA one',
        proves: 'the refusal itself. Cited to the test rather than to the '
            'group named for this row: a group is a container and asserts '
            'nothing on its own');
    provenIn('packages/at_client/test/jws_envelope_test.dart',
        'the control arm: both signatures valid, and it verifies',
        proves: 'that the refusal above is about the corruption rather than '
            'about two-signature envelopes being unreadable');
    provenIn('packages/at_client/test/jws_envelope_test.dart',
        'and the strongest is chosen however the entries are ordered',
        proves: 'selection is by strength, not by the signer\'s ordering');
  });

  test('UC-G1.8 · the rollout-1 signing key stays verifiable after rollout 2',
      () {
    // GIVEN an envelope signed at rollout 1 by the enrollment's RSA-2048
    //       SIGNING key — the one it holds from birth.
    // WHEN  the enrollment moves to rollout 2, mints ML-DSA-65, retires the
    //       RSA key and republishes _apsk as an array.
    // THEN  the stored envelope still verifies against the RSA key's retired
    //       entry, including where a retained entry names the same algorithm
    //       as an active one.
    provenIn('packages/at_client/test/jws_envelope_test.dart',
        'an envelope signed by the retained key still verifies',
        proves: 'the retained entry is tried, not just the active one — two '
            'keys under one algorithm, which is the case a first-wins lookup '
            'would get wrong');
    provenIn('packages/at_client/test/jws_envelope_test.dart',
        'a signature under neither key is still refused',
        proves: 'the control: trying every advertised key is not trying every '
            'key');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'an envelope signed before the withdrawal still verifies',
        proves: 'the same property across a real stage transition rather than '
            'a hand-built advertisement');
  });

  test('UC-G1.9 · a retired algorithm still verifies history', () {
    // GIVEN an algorithm dropped from the in-use set.
    // THEN  new envelopes carry no signature of it, its _apsk entry remains
    //       with status retired, and an envelope signed with it before the
    //       drop still verifies.
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'retires the superseded key and mints its replacement',
        proves: 'the transition itself: what leaves the in-use set stops '
            'signing');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'advertises the retired key beside the new one',
        proves: 'the entry remains rather than being withdrawn — withdrawing '
            'it would retroactively unverify everything it signed');
  });

  test(
      'UC-G1.9a · the client mints what the in-use set names, advertising '
      'before filing', () {
    // GIVEN an enrollment holding no signing key of its own and a preference
    //       whose in-use set names one.
    // WHEN  the client starts.
    // THEN  it mints that keypair, advertises it, and only then files it, so
    //       no envelope is ever signed under a key the advertisement does not
    //       name. A second start mints nothing; an empty set mints nothing.
    //
    // The one row of this cluster that was true as written — and the only one
    // written in the same commit as the code it describes.
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'mints, advertises and files the algorithm the set names',
        proves: 'the mint itself, and that the key reaches the keyfile');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'publishes BEFORE filing',
        proves: 'the ordering, which is the whole point: filing first makes '
            'the client sign under a key its advertisement does not name, and '
            'every envelope written in that window is permanently '
            'unverifiable');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'publishes the record itself rather than sending enroll:update',
        proves: 'the second branch — a client with no enrollment record '
            'writes _apsk directly');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'a second run mints nothing',
        proves: 'idempotence');
    provenIn('packages/at_client/test/signing_key_minting_test.dart',
        'an empty in-use set mints nothing',
        proves: 'the 3.x default does not start minting on upgrade');
  });
}
