/// X-Wing hybrid KEM (draft-connolly-cfrg-xwing-kem-10) fixed byte sizes,
/// shared by [XWingFfiAlgo] and [XWingPureDartAlgo] so both enforce
/// identical lengths.
abstract final class XWingSizes {
  /// Secret (decapsulation) key size — the 32-byte seed everything else is
  /// expanded from.
  static const int seedLength = 32;

  /// Public (encapsulation) key size: `pk_M || pk_X` (1184 + 32).
  static const int publicKeyLength = 1216;

  /// Ciphertext size: `ct_M || ct_X` (1088 + 32).
  static const int ciphertextLength = 1120;

  /// Shared secret size.
  static const int sharedSecretLength = 32;
}
