import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:better_cryptography/better_cryptography.dart';

/// A factory class to create AES-CTR encryption algorithms based on the key length.
///
/// The `AesCtrFactory` class provides a static method to create an instance of
/// the `AesCtr` encryption algorithm. The key length of the provided `AESKey`
/// determines the specific variant of AES-CTR to be instantiated.
class AesCtrFactory {
  /// Creates an `AesCtr` encryption algorithm based on the key length of the given [aesKey].
  ///
  /// The `aesKey` must have a length of 16, 24, or 32 bytes to correspond to AES-128, AES-192,
  /// or AES-256 respectively. A `MacAlgorithm.empty` is used for each variant.
  ///
  /// Throws an [AtEncryptionException] if the provided key length is invalid.
  ///
  /// Example usage:
  /// ```dart
  /// AESKey aesKey =AESKey.generate(32);//pass the length in bytes
  /// AesCtr encryptionAlgo = AesCtrFactory.createEncryptionAlgo(aesKey);
  /// ```
  ///
  /// - [aesKey]: An instance of `AESKey` containing the encryption key.
  /// - Returns: An instance of `AesCtr` configured for the appropriate key length.
  ///
  /// Supported key lengths:
  /// - 16 bytes for AES-128
  /// - 24 bytes for AES-192
  /// - 32 bytes for AES-256
  static AesCtr createEncryptionAlgo(AESKey aesKey) {
    switch (aesKey.getLength()) {
      case 16:
        return AesCtr.with128bits(macAlgorithm: MacAlgorithm.empty);
      case 24:
        return AesCtr.with192bits(macAlgorithm: MacAlgorithm.empty);
      case 32:
        return AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      default:
        throw AtEncryptionException(
            'Invalid AES key length. Valid lengths are 16/24/32 bytes');
    }
  }
}
