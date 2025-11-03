import 'package:at_auth/at_auth.dart' show KeyIOMixin, WrittenAtKeysIo, AtKeys;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:hive/hive.dart' show Hive;

/// Implementation of WrittenAtKeysIo using Keychain storage
/// Uses KeyChainManager to perform the CRUD operations related to keychains
///
/// This is the main class to interact with keychain for storing and retrieving AtKeys
class KeychainAtKeysIo extends WrittenAtKeysIo with KeyIOMixin {
  KeychainStorage keychainStorage;
  KeychainAtKeysIo({KeychainStorage? keychainStorage})
      : keychainStorage = keychainStorage ?? KeychainStorage();

  @override
  Future<AtKeys> read(String atSign) async {
    final atsignKey = await keychainStorage.getAtsign(atSign);
    if (atsignKey == null) {
      throw AtKeyException(
          'AtsignKey not found in keychain for atSign: $atSign');
    }
    return atsignKey;
  }

  @override
  Future<void> write(String atSign, AtKeys? atKeys) async {
    atKeys ??= await keychainStorage.getAtsign(atSign) ??
        generateKeyPairs(atSign: atSign);
    atKeys.metadata['atsign'] = atSign;
    atKeys.metadata['hiveSecret'] ??=
        String.fromCharCodes(Hive.generateSecureKey());
    await keychainStorage.appendAtKeysToKeychain(keys: atKeys);
  }
}
