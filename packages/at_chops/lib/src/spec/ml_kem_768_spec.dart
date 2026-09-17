import 'dart:typed_data';

/// FIPS 203 ML-KEM-768 fixed byte sizes and input validators — the single
/// source of truth shared by `MlKem768FfiAlgo` and `MlKem768PureDartAlgo` so
/// both enforce identical public-key and ciphertext lengths.
///
/// Deliberately no `secretKeyBytes`: a ML-KEM-768 secret key means different
/// things per backend — 2400 raw bytes for the pure-Dart backend, an opaque
/// 8-byte process-lifetime handle for the FFI backend (OpenSSL's EVP API
/// does not expose raw ML-KEM secret-key bytes). A shared constant here
/// would be misleading rather than useful.
abstract final class MlKem768Sizes {
  /// Raw public key size.
  static const int publicKeyBytes = 1184;

  /// Ciphertext size.
  static const int ciphertextBytes = 1088;

  /// Shared secret size.
  static const int sharedSecretBytes = 32;

  /// Throws [ArgumentError] unless [publicKey] is exactly [publicKeyBytes]
  /// long.
  static void validatePublicKey(Uint8List publicKey) {
    if (publicKey.length != publicKeyBytes) {
      throw ArgumentError.value(publicKey.length, 'publicKey',
          'ML-KEM-768 public key must be $publicKeyBytes bytes');
    }
  }

  /// Throws [ArgumentError] unless [ciphertext] is exactly [ciphertextBytes]
  /// long.
  static void validateCiphertext(Uint8List ciphertext) {
    if (ciphertext.length != ciphertextBytes) {
      throw ArgumentError.value(ciphertext.length, 'ciphertext',
          'ML-KEM-768 ciphertext must be $ciphertextBytes bytes');
    }
  }
}
