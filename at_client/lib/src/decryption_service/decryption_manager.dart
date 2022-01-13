import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/decryption_service/local_key_decryption.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
import 'package:at_commons/at_commons.dart';

///The manager class for [AtKeyDecryption]
class AtKeyDecryptionManager {
  /// Return the relevant instance of [AtKeyDecryption] for the given [AtKey]
  static AtKeyDecryption get(AtKey atKey, String currentAtSign) {
    // If sharedBy not equals currentAtSign, return SharedKeyDecryption
    // Eg: currentAtSign is @bob and key is phone@alice
    if (atKey.sharedBy != currentAtSign) {
      return SharedKeyDecryption();
    }
    // Return SelfKeyDecryption for hidden key.
    // Eg: currentAtSign is @bob and _phone.wavi@bob (or) phone@bob
    if (atKey.sharedWith == null && atKey.sharedBy == currentAtSign ||
        atKey.key.startsWith('_')) {
      return SelfKeyDecryption();
    }
    // Returns LocalKeyDecryption to for the keys present in local storage.
    // Eg. currentAtSign is @bob
    // @bob:phone@bob
    // @alice:phone@bob
    return LocalKeyDecryption();
  }
}
