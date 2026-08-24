import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part G1 — signature agility, the rollout matrix (`acceptance.md` 16.5).
///
/// The two rows measured by the programme pair in `tests/pq_matrix/`: what a
/// **deployed** peer makes of a rollout-1 sender, and whether every stage can
/// read every other stage's signature. Both are cross-build or cross-stage
/// questions, so both run as separate processes against a live atServer —
/// no single process can hold two versions of at_client.
void main() {
  test('UC-G1.14 · pqReady is invisible to a deployed peer', () {
    // GIVEN a sender at rollout 1 — an ML-DSA-65 authentication key and a
    //       freshly minted RSA-2048 signing key.
    // WHEN  a published-arm client (at_client 3.14.0 from pub.dev) fetches
    //       that enrollment's _apsk.
    // THEN  it reads a String that base64-decodes as an RSA public key,
    //       exactly as for a `now` sender — the released reader cannot tell
    //       the two stages apart.
    provenIn('tests/at_functional_test/test/pq_released_peer_test.dart',
        'UC-G1.14 · pqReady is invisible to a deployed peer',
        proves: 'the released reader\'s own verdict, with two positive '
            'controls: rollout 1 must publish a DIFFERENT key from now, and '
            'rollout 2 must fail the same parse — without which the row '
            'passes for a harness where no stage does anything');
  });

  test('UC-G1.15 · every rollout stage verifies every other stage\'s envelope',
      () {
    // GIVEN a sender and a receiver, each at one of now, rollout1, rollout2.
    // WHEN  the sender signs an envelope at its stage and the receiver fetches
    //       the sender's _apsk and verifies it with its own build.
    // THEN  all nine cells verify. rollout2 → rollout1 is the cell it exists
    //       for: an ML-DSA-65 signature read by a client that signs RSA-2048.
    provenIn('tests/at_functional_test/test/pq_posture_grid_test.dart',
        'UC-G1.15 · every posture verifies every other posture',
        proves: 'nine live cells, and the assertion that makes them mean '
            'something: rollout2 must emit exactly [ML-DSA-65] and now must '
            'not. Measured 2026-08-18 — mutating rollout2 to resolve as '
            'rollout1 leaves ALL NINE cells passing, because a sender signing '
            'RSA verifies everywhere too, so the algorithm assertion is the '
            'only thing that discriminates');
  });
}
