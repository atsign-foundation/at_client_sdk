import 'package:at_auth/at_auth.dart' show KeyIOMixin, WrittenAtKeysIo, AtKeys;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:hive/hive.dart' show Hive;

/// Implementation of WrittenAtKeysIo using Keychain storage
/// Uses KeyChainManager to perform the CRUD operations related to keychains
///
/// This is the main class to interact with keychain for storing and retrieving AtKeys
class KeychainAtKeysIo extends WrittenAtKeysIo with KeyIOMixin {
  KeyChainWrapper keychainManager;
  KeychainAtKeysIo({KeyChainWrapper? keychainManager})
      : keychainManager = keychainManager ?? KeyChainWrapper();

  @override
  Future<AtKeys> read(String atSign) async {
    final atsignKey = await keychainManager.getAtSign(name: atSign);
    if (atsignKey == null) {
      throw AtKeyException(
          'AtsignKey not found in keychain for atSign: $atSign');
    }
    return atsignKey;
  }

  @override
  Future<void> write(String atSign, AtKeys? atKeys) async {
    atKeys ??= await keychainManager.getAtSign(name: atSign) ??
        generateKeyPairs(atSign: atSign);
    atKeys.metadata['atsign'] = atSign;
    atKeys.metadata['hiveSecret'] ??=
        String.fromCharCodes(Hive.generateSecureKey());
    await keychainManager.putAtSign(atKeys: atKeys);
  }
}
