import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';

/// The manager class for [AtKeyEncryption]
class AtKeyEncryptionManager {
  /// Accepts the [AtKey] and currentAtSign and returns the relevant
  /// [AtKeyEncryption] subclass.
  late AtClient _atClient;

  static final AtKeyEncryptionManager _singleton =
      AtKeyEncryptionManager._internal();

  AtKeyEncryptionManager._internal();

  factory AtKeyEncryptionManager.getInstance(AtClient atClient) {
    _singleton._atClient = atClient;
    return _singleton;
  }

  AtKeyEncryption get(AtKey atKey, String currentAtSign) {
    // If atKey is sharedKey, return sharedKeyEncryption
    // Eg. @bob:phone.wavi@alice. and @alice is currentAtSign.
    // else returns SelfKeyEncryption.
    //
    // For keys like '@alice:phone@alice', a self encryption should be performed.
    // Setting the following condition in OR clause as well to support instances of
    // concrete AtKey class - "atKey.sharedWith != null && atKey.sharedWith != currentAtSign"
    if ((atKey is SharedKey &&
            atKey.sharedWith != null &&
            atKey.sharedWith != currentAtSign) ||
        atKey.sharedWith != null && atKey.sharedWith != currentAtSign) {
      return SharedKeyEncryption(_atClient);
    }
    return SelfKeyEncryption();
  }
}
