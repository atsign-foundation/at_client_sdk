import 'package:at_commons/at_commons.dart';

/// Abstract class for defining Crytographic schemes
/// Extendable to allow for pluggable encryption schemes
abstract class CryptoScheme {
  /// Returns the encryptedValue of the given [value]
  ///
  /// Returns a String for a text value.
  ///
  /// Returns `List<int>` for a stream data.
  ///
  /// Throws [KeyNotFoundException] if any of the encryption keys are not found.
  ///
  /// Throws [AtClientException] if invalid value type is passed.
  Future<dynamic> encrypt(AtKey atKey, dynamic value);

  /// Returns the decrypted value for the given encrypted value.
  ///
  /// Throws [IllegalArgumentException] if encrypted value is null.
  ///
  /// Throws [KeyNotFoundException] if encryption keys are not found.
  Future<dynamic> decrypt(AtKey atKey, dynamic value);

  /// Happens during registration of cryptoschemes in the registry.
  /// Ensures setup of essential keys for enc/dec of whatever the scheme requires
  /// ie: shared_keys, public/private keys, etc
  Future<void> register();
}
