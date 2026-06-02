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
