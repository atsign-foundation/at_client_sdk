import 'package:at_commons/at_commons.dart';

///The abstract class for decrypting the value of [AtKey]
abstract class AtKeyDecryption {
  /// Returns the decrypted value for the given encrypted value.
  ///
  /// Throws [IllegalArgumentException] if encrypted value is null.
  ///
  /// Throws [KeyNotFoundException] if encryption keys are not found.
  Future<dynamic> decrypt(AtKey atKey, dynamic value);
}
