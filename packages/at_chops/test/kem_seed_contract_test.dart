import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

/// The seed contract every KEM backend shares.
///
/// It exists because `generateKeyPair`'s `secretKey` means different things on
/// different backends, and a caller that has to persist a key cannot see the
/// difference: X-Wing's secret key IS its 32-byte seed, while ML-KEM's is an
/// expanded decapsulation key that no seeded call reproduces. Code written
/// against X-Wing therefore stores the right bytes by accident, and the same
/// code silently stores unrecoverable ones for ML-KEM.
void main() {
  final backends = <String, AtKemAlgorithm>{
    'X-Wing': XWingPureDartAlgo.instance,
    'ML-KEM-768': MlKem768PureDartAlgo.instance,
    'ML-KEM-1024': MlKem1024PureDartAlgo.instance,
  };

  group('every backend honours the seed contract', () {
    backends.forEach((name, kem) {
      test('$name: a seed reproduces its key pair exactly', () async {
        final Uint8List seed = kem.newSeed();
        final first = await kem.keyPairFromSeed(seed);
        final second = await kem.keyPairFromSeed(seed);

        expect(second.publicKey, first.publicKey);
        expect(second.secretKey, first.secretKey);
      });

      test('$name: a pair recovered from a seed actually decapsulates',
          () async {
        // The round-trip above only shows determinism. This shows the recovered
        // secret key is the one that opens what was sealed to the recovered
        // public key — which is what a restart depends on.
        final pair = await kem.keyPairFromSeed(kem.newSeed());
        final enc = await kem.encapsulate(pair.publicKey);

        expect(await kem.decapsulate(pair.secretKey, enc.ciphertext),
            enc.sharedSecret);
      });

      test('$name: newSeed draws fresh randomness', () async {
        expect(kem.newSeed(), isNot(kem.newSeed()));
      });

      test('$name: a wrong-length seed is refused', () async {
        expect(() => kem.keyPairFromSeed(Uint8List(7)), throwsArgumentError);
      });
    });
  });

  test('a persisted `secretKey` is recoverable for X-Wing and lost for ML-KEM',
      () async {
    // The two arms differ in exactly the way the contract exists to hide, and
    // they must genuinely differ or this proves nothing: X-Wing's secret key
    // equals its seed, ML-KEM-1024's does not and cannot be fed back as one.
    final xWing = XWingPureDartAlgo.instance;
    final xWingSeed = xWing.newSeed();
    final xWingPair = await xWing.keyPairFromSeed(xWingSeed);
    expect(xWingPair.secretKey, xWingSeed,
        reason: 'an X-Wing secret key IS the seed, so storing either works');

    final mlKem = MlKem1024PureDartAlgo.instance;
    final mlKemSeed = mlKem.newSeed();
    final mlKemPair = await mlKem.keyPairFromSeed(mlKemSeed);
    expect(mlKemPair.secretKey, isNot(mlKemSeed));
    expect(
        mlKemPair.secretKey, hasLength(MlKem1024PureDartAlgo.secretKeyLength),
        reason: 'it is the expanded decapsulation key, 3168 bytes to the '
            'seed\'s 64');
    expect(
        () => mlKem.keyPairFromSeed(mlKemPair.secretKey), throwsArgumentError,
        reason: 'so code that persisted `secretKey` — correct for X-Wing — '
            'cannot recover an ML-KEM key at all');
  });
}
