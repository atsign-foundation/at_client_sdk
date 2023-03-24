import 'package:at_commons/at_commons.dart';

/// The abstract class for EncryptionService.
abstract class AtKeyEncryption {
  /// Returns the encryptedValue of the given [value]
  ///
  /// Returns a String for a text value.
  ///
  /// Returns List<int> for a stream data.
  ///
  /// Throws [KeyNotFoundException] if any of the encryption keys are not found.
  ///
  /// Throws [AtClientException] if invalid value type is passed.
  Future<dynamic> encrypt(AtKey atKey, dynamic value,
      {bool storeSharedKeyEncryptedWithData = true});
}
