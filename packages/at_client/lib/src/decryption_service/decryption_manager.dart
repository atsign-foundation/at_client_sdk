import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/decryption_service/local_key_decryption.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';

///The manager class for [AtKeyDecryption]
class AtKeyDecryptionManager {
  late AtClient _atClient;

  static final AtKeyDecryptionManager _singleton =
      AtKeyDecryptionManager._internal();

  AtKeyDecryptionManager._internal();

  factory AtKeyDecryptionManager.getInstance(AtClient atClient) {
    _singleton._atClient = atClient;
    return _singleton;
  }

  /// Return the relevant instance of [AtKeyDecryption] for the given [AtKey]
  AtKeyDecryption get(AtKey atKey, String currentAtSign) {
    // If sharedBy not equals currentAtSign, return SharedKeyDecryption
    // Eg: currentAtSign is @bob and key is phone@alice
    if (atKey.sharedBy != currentAtSign) {
      return SharedKeyDecryption();
    }
    // Return SelfKeyDecryption for self keys.
    // Eg: currentAtSign is @bob and _phone.wavi@bob (or) phone@bob (or) @bob:phone@bob
    if (((atKey.sharedWith == null || atKey.sharedWith == currentAtSign) &&
            atKey.sharedBy == currentAtSign) ||
        atKey.key!.startsWith('_')) {
      return SelfKeyDecryption();
    }
    // Returns LocalKeyDecryption to for the keys present in local storage
    // that are sharedWith other atSign's.
    // @alice:phone@bob
    return LocalKeyDecryption(_atClient);
  }
}
