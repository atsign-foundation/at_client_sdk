import 'dart:convert';
import 'dart:typed_data';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_keychain/flutter_keychain.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:crypton/crypton.dart';
import 'package:at_client_mobile/src/auth_constants.dart';

class KeyChainManager {
  static final KeyChainManager _singleton = KeyChainManager._internal();

  static final _logger = AtSignLogger('KeyChainUtil');

  KeyChainManager._internal();

  factory KeyChainManager.getInstance() {
    return _singleton;
  }

  ///detemines whether to check for data in Flutterkeychain or not.
  bool _isKeychainCheck = false;

  ///FlutterSecureStorage upon which all CRUD operations will be performed.
  ///Throws [assertionError] if [atsign] is null or empty.
  final _storage = FlutterSecureStorage();
  Future<List<int>> getHiveSecretFromKeychain(String atsign) async {
    assert(atsign != null && atsign.isNotEmpty);
    List<int> secretAsUint8List;
    try {
      var hiveSecretString = await getValue(atsign, KEYCHAIN_HIVE_SECRET);

      if (hiveSecretString == null) {
        secretAsUint8List = _generatePersistenceSecret();
        hiveSecretString = String.fromCharCodes(secretAsUint8List);
        await putValue(atsign, KEYCHAIN_HIVE_SECRET, hiveSecretString);
      } else {
        secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
      }
    } catch (exception) {
      _logger.severe(
          'exception in getHiveSecretFromKeychain : ${exception.toString()}');
    }
    return secretAsUint8List;
  }

  ///Returns list of @signs stored in Flutterstorage.
  Future<List<String>> getAtSignListFromKeychain() async {
    var atsignMap = await _getAtSignMap();
    if (atsignMap.isEmpty) {
      return null;
    }
    var atsigns = atsignMap.keys.toList();
    _logger.info('Retrieved atsigns $atsigns from Keychain');
    return atsigns;
  }

  ///Returns [KEYCHAIN_SECRET] for [atsign].
  Future<String> getSecretFromKeychain(String atsign) async {
    var secret;
    try {
      assert(atsign != null && atsign != '');
      var secretString = await getValue(atsign, KEYCHAIN_SECRET);
      secret = secretString;
    } catch (e) {
      _logger.severe('Exception in getSecretFromKeychain :${e.toString()}');
    }
    return secret;
  }

  /// Use [getValue]
  @deprecated
  Future<String> getPrivateKeyFromKeyChain(String atsign) async {
    var pkamPrivateKey;
    try {
      assert(atsign != null && atsign != '');
      pkamPrivateKey = await _storage.read(key: atsign + '_pkam_private_key');
    } on Exception catch (e) {
      _logger.severe('exception in getPrivateKeyFromKeyChain :${e.toString()}');
    }
    return pkamPrivateKey;
  }

  /// Use [getValue]
  @deprecated
  Future<String> getPublicKeyFromKeyChain(String atsign) async {
    var pkamPublicKey;
    try {
      assert(atsign != null && atsign != '');
      pkamPublicKey = await _storage.read(key: atsign + '_pkam_public_key');
    } on Exception catch (e) {
      _logger.severe('exception in getPublicKeyFromKeyChain :${e.toString()}');
    }
    return pkamPublicKey;
  }

  ///Returns String value of [key] for [atsign] into FlutterSecureStorage.
  Future<String> getValue(String atsign, String key) async {
    var value;
    try {
      key = _formKey(atsign: atsign, key: key);
      value = await _storage.read(key: key);
    } on Exception catch (e) {
      _logger.severe(
          'flutter keychain - exception in get value for ${key} :${e.toString()}');
    }
    return value;
  }

  ///Stores [value] for [atsign] [key] into FlutterSecureStorage.
  Future<String> putValue(String atsign, String key, String value) async {
    try {
      key = _formKey(atsign: atsign, key: key);
      await _storage.write(key: key, value: value);
    } catch (e) {
      _logger.severe(
          'flutter keychain - exception in put value for ${key} :${e.toString()}');
    }
    return value;
  }

  ///Returns `true` on successful storing of [secret]/[privateKey]/[publicKey] for [atSign].
  ///Throws [assertionError] if [atSign] is null or empty.
  Future<bool> storeCredentialToKeychain(String atSign,
      {String secret, String privateKey, String publicKey}) async {
    var success = false;
    try {
      assert(atSign != null && atSign != '');
      atSign = atSign.trim().toLowerCase().replaceAll(' ', '');
      if (secret != null) {
        secret = secret.trim().toLowerCase().replaceAll(' ', '');
        await putValue(atSign, KEYCHAIN_SECRET, secret);
      }
      await _saveAtSignToKeychain(atSign);
      await storePkamKeysToKeychain(atSign,
          privateKey: privateKey, publicKey: publicKey);
      success = true;
    } catch (exception) {
      _logger.severe(
          'exception in storeCredentialToKeychain :${exception.toString()}');
    }
    return success;
  }

  ///Stores [privateKey], [publicKey] for [atsign].
  ///Throws [assertionError] if [atSign] is null or empty.
  Future<void> storePkamKeysToKeychain(String atsign,
      {String privateKey, String publicKey}) async {
    assert(atsign != null && atsign != '');
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    try {
      if (privateKey != null) {
        await putValue(
            atsign, KEYCHAIN_PKAM_PRIVATE_KEY, privateKey.toString());
      }
      if (publicKey != null) {
        await putValue(atsign, KEYCHAIN_PKAM_PUBLIC_KEY, publicKey.toString());
      }
    } catch (exception) {
      _logger.severe(
          'exception in storeCredentialToKeychain :${exception.toString()}');
    }
  }

  ///Returns a generated secure encryption key.
  List<int> _generatePersistenceSecret() {
    return Hive.generateSecureKey();
  }

  ///Returns a generated random [RSAKeypair].
  RSAKeypair generateKeyPair() {
    var rsaKeypair = RSAKeypair.fromRandom();
    return rsaKeypair;
  }

  ///Returns a cramSecret for [atSign].
  Future<String> getCramSecret(String atSign) async {
    return getSecretFromKeychain(atSign);
  }

  ///Returns a private key for [atSign].
  Future<String> getPkamPrivateKey(String atSign) async {
    return getValue(atSign, KEYCHAIN_PKAM_PRIVATE_KEY);
  }

  ///Returns a publicKey for [atSign].
  Future<String> getPkamPublicKey(String atSign) async {
    return getValue(atSign, KEYCHAIN_PKAM_PUBLIC_KEY);
  }

  ///Returns an encryption Privatekey for [atSign].
  Future<String> getEncryptionPrivateKey(String atSign) async {
    return getValue(atSign, KEYCHAIN_ENCRYPTION_PRIVATE_KEY);
  }

  ///Returns an encryption Publickey for [atSign].
  Future<String> getEncryptionPublicKey(String atSign) async {
    return getValue(atSign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY);
  }

  ///Returns a self encryption AES key for [atSign].
  Future<String> getSelfEncryptionAESKey(String atSign) async {
    return getValue(atSign, KEYCHAIN_SELF_ENCRYPTION_KEY);
  }

  ///Returns a hivesecret Privatekey for [atSign].
  Future<List<int>> getKeyStoreSecret(String atSign) async {
    return getHiveSecretFromKeychain(atSign);
  }

  ///Returns an atsign.
  Future<String> getAtSign() async {
    var atSignList = await getAtSignListFromKeychain();
    return atSignList == null ? atSignList : atSignList[0];
  }

  ///Stores [atsign] along with the primary status into FlutterSecureStorage.
  Future<void> _saveAtSignToKeychain(String atsign) async {
    var atsignMap = <String, bool>{};
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    atsignMap = await _getAtSignMap();
    if (atsignMap.isNotEmpty) {
      atsignMap[atsign] =
          atsignMap.containsKey(atsign) ? atsignMap[atsign] : false;
    }
    //by default first stored @sign in the keychain will be the primary one.
    else {
      atsignMap[atsign] = true;
    }
    await _storeAtsign(atsignMap);
  }

  ///Converts [atsignMap] to  `String` type and then stores for `KEYCHAIN_ATSIGN`.
  Future<void> _storeAtsign(Map<String, bool> atsignMap) async {
    var value = jsonEncode(atsignMap);
    await putValue(null, KEYCHAIN_ATSIGN, value);
  }

  ///Returns a map of atsigns with their primary status.
  Future<Map<String, bool>> _getAtSignMap() async {
    var atsignMap = <String, bool>{};
    var atsignSecondMap = <String, bool>{};
    var value;
    if (_isKeychainCheck) {
      value = await getKeychainValue(null, KEYCHAIN_ATSIGN);
    } else {
      value = await getValue(null, KEYCHAIN_ATSIGN);
    }

    if (value != null && value.isNotEmpty) {
      if (!value.contains(':')) {
        atsignMap[value] = true;
        await _storeAtsign(atsignMap);
        return atsignMap;
      }
      var decodedJson = jsonDecode(value);
      decodedJson.forEach((key, value) {
        if (value) {
          atsignMap[key.toString()] = value as bool;
        } else {
          atsignSecondMap[key.toString()] = value as bool;
        }
      });
      atsignMap.addAll(atsignSecondMap);
      atsignSecondMap.clear();
    }
    _logger.info('atsignMap: $atsignMap');
    return atsignMap;
  }

  ///Returns @sign map with the primary status.
  Future<Map<String, bool>> getAtsignsWithStatus() async {
    return await _getAtSignMap();
  }

  ///Returns `true` on making the status of [atsign] as primary.
  Future<bool> makeAtSignPrimary(String atsign) async {
    //check whether given atsign is an already active atsign
    var atsignMap = await _getAtSignMap();
    if (atsignMap.isEmpty || !atsignMap.containsKey(atsign)) {
      return false;
    }
    var activeAtsign =
        atsignMap.keys.firstWhere((key) => atsignMap[key] == true);
    if (activeAtsign != null && activeAtsign != atsign) {
      atsignMap[activeAtsign] = false;
    }
    atsignMap[atsign] = true;
    await _storeAtsign(atsignMap);
    return true;
  }

  ///Deletes [atsign] from FlutterSecureStorage.
  Future<void> deleteAtSignFromKeychain(String atsign) async {
    var atsignMap = await _getAtSignMap();
    if (!atsignMap.containsKey(atsign)) {
      return;
    }
    var isDeletedActiveAtsign = atsignMap[atsign];
    atsignMap.remove(atsign);
    if (atsignMap.isEmpty) {
      await _storage.delete(key: KEYCHAIN_ATSIGN);
      return;
    }
    if (isDeletedActiveAtsign) {
      atsignMap[atsignMap.keys.first] = true;
    }
    await _storeAtsign(atsignMap);
  }

  ///Deletes the [atsign] and it's public, private keys from FlutterSecureStorage.
  Future<void> resetAtSignFromKeychain(String atsign) async {
    await deleteAtSignFromKeychain(atsign);
    await _storage.delete(key: atsign + ':_pkam_private_key');
    await _storage.delete(key: atsign + ':_pkam_public_key');
  }

  ///migrates all keys from flutterKeyChain to FlutterKeyStorage.
  Future<void> migrateToFlutterKeyStorage() async {
    var key;
    try {
      var flutterKeyStorageMigrated = 'keystorageMigrated';
      var isMigrated = await _storage.read(key: flutterKeyStorageMigrated);
      if (isMigrated == 'true') {
        _logger
            .info('All keys from flutterkeychain got migrated to keystorage');
        return;
      }
      _isKeychainCheck = true;
      var atsignList = await getAtSignListFromKeychain();

      //when app is installed with no data in flutterkeychain.
      if (atsignList == null) {
        await _storage.write(key: flutterKeyStorageMigrated, value: 'true');
        _isKeychainCheck = false;
        return;
      }
      //storing in temp list so that two unique keys will be stored only once to keystorage.
      var migratingKeysList = [...KEYCHAIN_KEYS_LIST];
      migratingKeysList.retainWhere((key) =>
          key != KEYCHAIN_ATSIGN && key != KEYCHAIN_SELF_KEYS_MIGRATED);
      var value = await getKeychainValue(null, KEYCHAIN_ATSIGN, true);
      await _storage.write(key: KEYCHAIN_ATSIGN, value: value);

      value = await getKeychainValue(null, KEYCHAIN_SELF_KEYS_MIGRATED, true);
      await _storage.write(key: KEYCHAIN_SELF_KEYS_MIGRATED, value: value);

      for (var atsign in atsignList) {
        for (var migratingKey in migratingKeysList) {
          migratingKey = _formKey(key: migratingKey, atsign: atsign);
          value = await getKeychainValue(atsign, migratingKey);
          if (value == null) {
            continue;
          }
          await _storage.write(key: migratingKey, value: value);
          await FlutterKeychain.remove(key: migratingKey);
        }
      }
      await _storage.write(key: flutterKeyStorageMigrated, value: 'true');

      //after successful migration unique keys will be removed.
      await FlutterKeychain.remove(key: KEYCHAIN_ATSIGN);
      await FlutterKeychain.remove(key: KEYCHAIN_SELF_KEYS_MIGRATED);

      _isKeychainCheck = false;
    } catch (err) {
      _logger.severe(
          'Migrating $key from keychain to keystorage throws ${err.toString()}');
    }
  }

  ///Fetches value from flutterKeychain
  Future<String> getKeychainValue(String atsign, String key,
      [bool isFormKey = false]) async {
    var value;
    try {
      if (isFormKey) key = _formKey(atsign: atsign, key: key);
      value = await FlutterKeychain.get(key: key);
    } on Exception catch (e) {
      _logger.severe(
          'flutter keychain - exception in get value for ${key} :${e.toString()}');
    }
    return value;
  }

  ///Returns `key` String by parsing it into the suitablevformat/.
  String _formKey({@required String key, String atsign}) {
    if (key == KEYCHAIN_HIVE_SECRET) {
      key = atsign + key;
    } else if (key == KEYCHAIN_ATSIGN || key == KEYCHAIN_SELF_KEYS_MIGRATED) {
      key = key;
    } else {
      key = atsign + ':' + key;
    }
    return key;
  }
}

enum KeyChainOperation { read, delete, write, deleteAll, readAll }
