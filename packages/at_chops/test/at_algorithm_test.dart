import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

/// One instance of each of the six [AtAlgorithm] families, all pure-Dart so
/// this file stays FFI-free.
///
/// Declaring this as `List<AtAlgorithm>` is itself the assertion: if any
/// family stops implementing [AtAlgorithm], this stops compiling.
final List<AtAlgorithm> allFamilies = [
  AesGcm256EncryptionAlgo(), // SymmetricEncryptionAlgorithm
  RsaEncryptionAlgo(), // ASymmetricEncryptionAlgorithm
  Ed25519SigningAlgo(), // AtSignatureAlgorithm
  SHA256HashingAlgo(), // AtHashingAlgorithm<List<int>, String>
  MlKem768PureDartAlgo.instance, // AtKemAlgorithm
  X25519PureDartAlgo.instance, // AtKeyAgreementAlgorithm
];

/// Exhaustive switch over [AtAlgorithm] with **no default arm**.
///
/// This compiles only because [AtAlgorithm] is sealed and every one of its
/// direct subtypes is covered. Drop `sealed`, or add a seventh family, and
/// the analyzer rejects this function — which is the whole point of the
/// umbrella for at_server.
String familyOf(AtAlgorithm algo) => switch (algo) {
      AtSignatureAlgorithm() => 'signature',
      SymmetricEncryptionAlgorithm() => 'symmetric',
      ASymmetricEncryptionAlgorithm() => 'asymmetric',
      AtKemAlgorithm() => 'kem',
      AtHashingAlgorithm() => 'hashing',
      AtKeyAgreementAlgorithm() => 'keyAgreement',
    };

void main() {
  group('AtAlgorithm', () {
    test('name is readable off the union type, without narrowing', () {
      expect(
          allFamilies.map((AtAlgorithm a) => a.name),
          equals(
              ['aesgcm256', 'rsa', 'ed25519', 'sha256', 'mlkem768', 'x25519']));
    });

    test('no algorithm reports an empty name', () {
      for (final AtAlgorithm algo in allFamilies) {
        expect(algo.name, isNotEmpty,
            reason: '${algo.runtimeType} has no name');
      }
    });

    test('an exhaustive switch reaches every family', () {
      expect(
          allFamilies.map(familyOf),
          equals([
            'symmetric',
            'asymmetric',
            'signature',
            'hashing',
            'kem',
            'keyAgreement',
          ]));
    });
  });
}
