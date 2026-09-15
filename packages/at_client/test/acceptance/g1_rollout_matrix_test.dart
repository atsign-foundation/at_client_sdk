import 'package:test/test.dart';

import 'proven_elsewhere.dart';

/// Part G1 — signature agility, the rollout matrix: what a deployed peer makes
/// of a rollout-1 sender, and whether every stage reads every other stage's
/// signature.
///
/// Both are proven in separate processes against a live atServer: no single
/// process can hold two versions of at_client.
void main() {
  test('UC-G1.14 · pqReady is invisible to a deployed peer', () {
    provenIn('tests/at_functional_test/test/pq_released_peer_test.dart',
        'UC-G1.14 · pqReady is invisible to a deployed peer',
        proves: 'the released reader\'s own verdict, with two positive '
            'controls: rollout 1 must publish a DIFFERENT key from now, and '
            'rollout 2 must fail the same parse — without which the row '
            'passes for a harness where no stage does anything',
        clauses: [
          'returns a String which base64-decodes as an RSA public key',
        ]);
  });

  test('UC-G1.15 · every rollout stage verifies every other stage\'s envelope',
      () {
    provenIn('tests/at_functional_test/test/pq_posture_grid_test.dart',
        'UC-G1.15 · every posture verifies every other posture',
        proves: 'nine live cells, and the assertion that makes them mean '
            'something: rollout2 must emit exactly [ML-DSA-65] and now must '
            'not. Measured 2026-08-18 — mutating rollout2 to resolve as '
            'rollout1 leaves ALL NINE cells passing, because a sender signing '
            'RSA verifies everywhere too, so the algorithm assertion is the '
            'only thing that discriminates. The round trip itself is asserted '
            'rather than printed: verification passes on the STRONGEST shared '
            'signature, so an envelope that lost one on the way through the '
            'atServer would verify exactly as well as one that did not',
        clauses: [
          'the algorithms the receiver saw are the ones the sender emitted',
        ]);
  });
}
