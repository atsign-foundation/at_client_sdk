import 'package:at_auth/at_auth.dart' show WrittenAtKeysIo, AtKeys;
import 'package:at_commons/at_commons.dart';
import 'package:hive/hive.dart' show Hive;

import 'keychain_storage.dart';

/// Implementation of WrittenAtKeysIo using Keychain storage
/// Uses KeyChainManager to perform the CRUD operations related to keychains
///
/// This is the main class to interact with keychain for storing and retrieving AtKeys
class KeychainAtKeysIo extends WrittenAtKeysIo {
  KeychainStorage keychainStorage;
  KeychainAtKeysIo({KeychainStorage? keychainStorage})
      : keychainStorage = keychainStorage ?? KeychainStorage();

  @override
  Future<AtKeys> read(String atSign) async {
    final AtKeys? atsignKey = await keychainStorage.getAtsign(atSign);
    if (atsignKey == null) {
      throw AtKeyException(
          'AtsignKey not found in keychain for atSign: $atSign');
    }
    return atsignKey;
  }

  @override
  Future<void> write(String atSign, AtKeys atKeys) async {
    atKeys.metadata['atsign'] = atSign;
    await keychainStorage.appendAtKeysToKeychain(keys: atKeys);
  }
}
