import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_commons/at_commons.dart';

/// The manager class for [AtKeyEncryption]
class AtKeyEncryptionManager {
  /// Accepts the [AtKey] and currentAtSign and returns the relevant
  /// [AtKeyEncryption] subclass.
  static AtKeyEncryption get(AtKey atKey, String currentAtSign) {
    // If atKey is sharedKey, return sharedKeyEncryption
    // Eg. @bob:phone.wavi@alice. and @bob is not the currentAtSign.
    // else returns SelfKeyEncryption.
    if (atKey is SharedKey ||
        atKey.sharedWith != null && atKey.sharedWith != currentAtSign) {
      return SharedKeyEncryption();
    }
    return SelfKeyEncryption();
  }
}
