/// Pins for [SigningAlgoType.strongestFirst] — the order a verifier uses to
/// choose which of several signatures on one envelope to check.
///
/// The order decides which signature is authoritative, so a change to it is a
/// change to what a fleet accepts: two builds that disagree about "strongest"
/// verify different entries of the same envelope and can reach opposite
/// verdicts. These pins make an edit here deliberate and reviewable.
library;

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('FROZEN: the signing strength order', () {
    test('the exact order, by wire name', () {
      // Raw literals rather than the enum members, so this pin survives a
      // rename and fails on a reorder — asserting through the members would
      // follow any change silently, which is the whole failure this exists to
      // catch.
      expect(SigningAlgoType.strongestFirst.map((a) => a.name).toList(), [
        'mldsa65',
        'rsa4096',
        'ed25519',
        'ecc_secp256r1',
        'rsa2048',
      ]);
    });

    test('every algorithm is ranked, exactly once', () {
      // The tripwire that matters. A new SigningAlgoType added without a place
      // in the order would otherwise be silently unrankable: strongestOf would
      // never return it, so an enrollment advertising only that algorithm would
      // be treated as advertising nothing, and refused for a reason naming the
      // wrong thing.
      expect(SigningAlgoType.strongestFirst.toSet(),
          SigningAlgoType.values.toSet(),
          reason: 'add the new member to strongestFirst, in the position its '
              'security level earns');
      expect(SigningAlgoType.strongestFirst,
          hasLength(SigningAlgoType.values.length),
          reason: 'a duplicate would make the order ambiguous where it looks '
              'total');
    });

    test('the post-quantum member is first, and that is not a close call', () {
      expect(SigningAlgoType.strongestFirst.first, SigningAlgoType.mldsa65,
          reason: 'the only member Shor does not break — no classical '
              'parameter size promotes anything above it');
    });

    test('declaration order is deliberately NOT the strength order', () {
      // Guards against someone "simplifying" strongestFirst away into
      // SigningAlgoType.values. The members are declared in the order they were
      // added, and reordering them is a wire change.
      expect(SigningAlgoType.strongestFirst, isNot(SigningAlgoType.values));
      expect(SigningAlgoType.values.first, SigningAlgoType.ecc_secp256r1);
      expect(SigningAlgoType.values.last, SigningAlgoType.mldsa65);
    });
  });

  group('strongestOf', () {
    test('picks the strongest present, not the first offered', () {
      expect(
          SigningAlgoType.strongestOf(
              [SigningAlgoType.rsa2048, SigningAlgoType.mldsa65]),
          SigningAlgoType.mldsa65);
      expect(
          SigningAlgoType.strongestOf(
              [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048]),
          SigningAlgoType.mldsa65,
          reason: 'the answer must not depend on the order the candidates '
              'arrive in — that order is the signer\'s choice, and letting it '
              'decide would hand the algorithm to whoever wrote the envelope');
    });

    test('an empty set has no strongest, rather than a default', () {
      expect(SigningAlgoType.strongestOf(const []), isNull,
          reason: 'a caller with nothing it understands must refuse outright; '
              'a default here would be a fallback to a key the signer never '
              'published');
    });

    test('a single candidate is its own strongest', () {
      for (final algo in SigningAlgoType.values) {
        expect(SigningAlgoType.strongestOf([algo]), algo);
      }
    });

    test('the full set resolves to the post-quantum one', () {
      expect(SigningAlgoType.strongestOf(SigningAlgoType.values),
          SigningAlgoType.mldsa65);
    });
  });
}
