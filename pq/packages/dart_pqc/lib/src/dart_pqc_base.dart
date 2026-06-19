import 'dart:typed_data';

/// A raw asymmetric key pair (public key + secret key as byte arrays).
final class PqcKeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  const PqcKeyPair({required this.publicKey, required this.secretKey});
}

/// The ciphertext and shared secret produced by [MlKem768Algorithm.encapsulate].
final class EncapsulationResult {
  final Uint8List ciphertext;
  final Uint8List sharedSecret;

  const EncapsulationResult({
    required this.ciphertext,
    required this.sharedSecret,
  });
}

/// Common interface for ML-KEM-768 implementations.
abstract interface class MlKem768Algorithm {
  /// Generate a fresh key pair.
  ///
  /// Optionally accepts a 64-byte [seed] (d||z) for deterministic generation
  /// (testing only — do not use a fixed seed in production).
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed]);

  /// Encapsulate a shared secret against [publicKey].
  ///
  /// Returns the ciphertext to send to the holder of the matching secret key,
  /// together with the shared secret that both parties will derive.
  Future<EncapsulationResult> encapsulate(Uint8List publicKey);

  /// Recover the shared secret from [ciphertext] using [secretKey].
  Future<Uint8List> decapsulate(Uint8List secretKey, Uint8List ciphertext);
}

/// Common interface for X25519 implementations.
abstract interface class X25519Algorithm {
  /// Generate a fresh X25519 key pair.
  ///
  /// Returns `(publicKey: 32 bytes, privateKey: 32 bytes)`.
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair();

  /// Perform X25519 DH: compute the shared secret from [privateKey] and [peerPublicKey].
  ///
  /// Returns a 32-byte shared secret.
  Future<Uint8List> dh(Uint8List privateKey, Uint8List peerPublicKey);
}

/// Common interface for X-Wing KEM (ML-KEM-768 + X25519 hybrid, draft-connolly-cfrg-xwing-kem-06).
///
/// Key sizes: pk=1216B  sk=2464B  ct=1120B  ss=32B
abstract interface class XWingAlgorithm {
  /// Generate a fresh X-Wing key pair.
  ///
  /// Optionally accepts a 96-byte [seed96] for deterministic generation:
  /// seed96[0:64] → ML-KEM-768 leg, seed96[64:96] → X25519 leg.
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed96]);

  /// Encapsulate a shared secret to [publicKey] (1216 B).
  Future<EncapsulationResult> encaps(Uint8List publicKey);

  /// Decapsulate: recover shared secret from [secretKey] (2464 B) and [ciphertext] (1120 B).
  Future<Uint8List> decaps(Uint8List secretKey, Uint8List ciphertext);
}

/// Common interface for ML-DSA-65 implementations (FIPS 204 lattice signatures).
///
/// Key sizes: pk=1952B  sk=4032B  sig≤3309B
abstract interface class MlDsa65Algorithm {
  /// Generate a fresh ML-DSA-65 key pair.
  Future<PqcKeyPair> generateKeyPair();

  /// Sign [message] with [secretKey] (4032 B). Returns a signature (≤3309 B).
  Future<Uint8List> sign(Uint8List secretKey, Uint8List message);

  /// Verify [signature] over [message] with [publicKey] (1952 B).
  Future<bool> verify(
      Uint8List publicKey, Uint8List message, Uint8List signature);
}

/// Common interface for Ed25519 implementations.
abstract interface class Ed25519Algorithm {
  /// Generate a fresh Ed25519 key pair.
  ///
  /// Returns `(publicKey: 32 bytes, privateKey: 32 bytes)`.
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair();

  /// Sign [message] with [privateKey]. Returns a 64-byte signature.
  Future<Uint8List> sign(Uint8List privateKey, Uint8List message);

  /// Verify [signature] over [message] with [publicKey].
  Future<bool> verify(Uint8List publicKey, Uint8List message, Uint8List signature);
}
