import 'package:at_auth/at_auth.dart' show KeyIOMixin, WrittenAtKeysIo, AtKeys;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart' show Hive;

/// Implementation of WrittenAtKeysIo using Keychain storage
/// Uses KeyChainManager to perform the CRUD operations related to keychains
///
/// This is the main class to interact with keychain for storing and retrieving AtKeys
class KeychainAtKeysIo extends WrittenAtKeysIo with KeyIOMixin {
  @visibleForTesting
  KeyChainManager keychainManager;
  KeychainAtKeysIo({KeyChainManager? keychainManager})
      : keychainManager = keychainManager ?? KeyChainManager();

  @override
  Future<AtKeys> read(String atSign) async {
    final atsignKey = await keychainManager.getAtSign(name: atSign);
    if (atsignKey == null) {
      throw AtKeyException(
          'AtsignKey not found in keychain for atSign: $atSign');
    }
    return atsignKey;
  }

  Future<List<AtKeys>> readAll() async {
    final atsigns = await keychainManager.getAllAtSigns();
    return atsigns;
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

  Future<void> deleteAllAtSigns() async {
    List<AtKeys> atKeysList = await readAll();
    for (AtKeys atKeys in atKeysList) {
      String atsign = atKeys.metadata['atsign'] as String;
      await keychainManager.deleteAtSign(atsign);
    }
  }
}
