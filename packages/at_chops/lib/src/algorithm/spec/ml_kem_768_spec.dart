/// FIPS 203 ML-KEM-768 fixed byte sizes shared by `MlKem768FfiAlgo` and
/// `MlKem768PureDartAlgo` so both enforce identical public-key and
/// ciphertext lengths.
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
}
