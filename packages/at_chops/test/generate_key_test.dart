import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

/// Successor to the old `key_gen_test.dart`, which tested the removed
/// `AESKey.generate`. Key generation now lives on each algorithm.
void main() {
  group('AesCtrEncryptionAlgo.generateKey', () {
    for (final keyLengthBytes in [16, 24, 32]) {
      test('generates a $keyLengthBytes-byte key', () {
        expect(AesCtrEncryptionAlgo(keyLengthBytes).generateKey(),
            hasLength(keyLengthBytes));
      });
    }

    test('generates a different key each call', () {
      final algo = AesCtrEncryptionAlgo(32);
      expect(algo.generateKey(), isNot(equals(algo.generateKey())));
    });

    test('the generated key is accepted by encrypt', () async {
      final algo = AesCtrEncryptionAlgo(24);
      final iv = InitialisationVector.random(AesCtrEncryptionAlgo.ivLength);
      await expectLater(
          algo.encrypt(Uint8List.fromList([1, 2, 3]), algo.generateKey(),
              iv: iv),
          completes);
    });
  });

  test('generateKey is reachable through the interface type', () {
    final List<SymmetricEncryptionAlgorithm> algos = [
      AesCtrEncryptionAlgo(16),
      AesGcm256EncryptionAlgo(),
    ];
    // A caller holding the interface gets a correctly sized key without
    // knowing which implementation it has.
    expect(algos.map((a) => a.generateKey().length), [16, 32]);
  });

  group('AesGcm256EncryptionAlgo.generateKey', () {
    test('generates a 256-bit key', () {
      expect(AesGcm256EncryptionAlgo().generateKey(),
          hasLength(AesGcm256EncryptionAlgo.keyLength));
    });

    test('generates a different key each call', () {
      final algo = AesGcm256EncryptionAlgo();
      expect(algo.generateKey(), isNot(equals(algo.generateKey())));
    });

    test('the generated key is accepted by encrypt', () async {
      final algo = AesGcm256EncryptionAlgo();
      final iv =
          InitialisationVector.random(AesGcm256EncryptionAlgo.nonceLength);
      await expectLater(
          algo.encrypt(Uint8List.fromList([1, 2, 3]), algo.generateKey(),
              iv: iv),
          completes);
    });
  });
}
