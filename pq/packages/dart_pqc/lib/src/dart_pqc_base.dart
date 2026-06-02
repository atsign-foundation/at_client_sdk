/// Core abstractions for dart_pqc.
///
/// [KeyPair] holds a raw public/secret key pair from [KemAlgorithm.generateKeyPair].
/// [EncapsulationResult] holds a ciphertext and the shared secret from [KemAlgorithm.encapsulate].
/// [KemAlgorithm] is the common interface every KEM implementation must satisfy.

import 'dart:typed_data';

/// A raw asymmetric key pair (public key + secret key as byte arrays).
final class PqcKeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  const PqcKeyPair({required this.publicKey, required this.secretKey});
}

/// The ciphertext and shared secret produced by [KemAlgorithm.encapsulate].
final class EncapsulationResult {
  final Uint8List ciphertext;
  final Uint8List sharedSecret;

  const EncapsulationResult({
    required this.ciphertext,
    required this.sharedSecret,
  });
}

/// Common interface for all KEM (Key Encapsulation Mechanism) algorithms.
abstract interface class KemAlgorithm {
  /// Human-readable algorithm name, e.g. `"ML-KEM-768"`.
  String get name;

  /// Generate a fresh key pair.
  ///
  /// Optionally accepts a 32-byte [seed] for deterministic generation (testing only).
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed]);

  /// Encapsulate a shared secret against [publicKey].
  ///
  /// Returns the ciphertext to send to the holder of the matching secret key,
  /// together with the shared secret that both parties will derive.
  Future<EncapsulationResult> encapsulate(Uint8List publicKey);

  /// Recover the shared secret from [ciphertext] using [secretKey].
  Future<Uint8List> decapsulate(Uint8List secretKey, Uint8List ciphertext);
}
