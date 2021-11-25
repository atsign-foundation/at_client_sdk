import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client_mobile/src/auth_constants.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_keychain/flutter_keychain.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:hive/hive.dart';

class KeyChainManager {
  static final KeyChainManager _singleton = KeyChainManager._internal();

  static final _logger = AtSignLogger('KeyChainUtil');

  KeyChainManager._internal();

  factory KeyChainManager.getInstance() {
    return _singleton;
  }

  BiometricStorageFile? _storage;

  Future<BiometricStorageFile> getBiometricStorageFile(String key) async {
    return await BiometricStorage().getStorage(key,
        options: StorageFileInitOptions(
          authenticationRequired: false,
        ));
  }

  Future<List<int>> getHiveSecretFromKeychain(String atsign) async {
    assert(atsign.isNotEmpty);
    List<int> secretAsUint8List = [];
    try {
      var hiveKey = atsign + '_hive_secret';
      _storage = await getBiometricStorageFile(hiveKey);
      var hiveSecretString = await _storage?.read();
      if (hiveSecretString == null) {
        secretAsUint8List = _generatePersistenceSecret();
        hiveSecretString = String.fromCharCodes(secretAsUint8List);
        await _storage?.write(hiveSecretString);
      } else {
        secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
      }
    } on Exception catch (exception) {
      _logger.severe(
          'exception in getHiveSecretFromKeychain : ${exception.toString()}');
    }

    return secretAsUint8List;
  }

  Future<List<String>?> getAtSignListFromKeychain() async {
    var atsignMap = await _getAtSignMap();
    if (atsignMap.isEmpty) {
      // no atsigns found in biometric storage
      // read entries from flutter keychain
      // for mobile platforms only
      if (Platform.isAndroid || Platform.isIOS) {
        atsignMap = await checkForValuesInFlutterKeychain();
        if (atsignMap.isEmpty) {
          return null;
        }
      } else {
        return null;
      }
    }
    var atsigns = atsignMap.keys.toList();
    _logger.info('Retrieved atsigns $atsigns from Keychain');
    return atsigns;
  }

  Future<Map<String, bool?>> checkForValuesInFlutterKeychain() async {
    var atsignMap = await _getAtSignMap(useFlutterKeychain: true);
    if (atsignMap.isNotEmpty) {
      var atsigns = atsignMap.keys.toList();
      await Future.forEach(atsigns, (String atsign) async {
        await Future.forEach(keychainKeys, (String keychainKey) async {
          try {
            assert(atsign.isNotEmpty);
            var value =
                await FlutterKeychain.get(key: atsign + ':' + keychainKey);
            putValue(atsign, keychainKey, value ?? '');
          } on Exception catch (e) {
            _logger.severe(
                'Exception in transferring keychain entries :${e.toString()}');
          }
        });
      });

      // verify and delete flutter keychain entry
      var atsignMapFromBS = await _getAtSignMap();
      if (mapEquals(atsignMap, atsignMapFromBS)) {
        var atsignsFromFK = atsignMap.keys.toList();
        await Future.forEach(atsignsFromFK, (String atsign) async {
          await Future.forEach(keychainKeys, (String keychainKey) async {
            try {
              assert(atsign.isNotEmpty);
              await FlutterKeychain.remove(key: atsign + ':' + keychainKey);
            } on Exception catch (e) {
              _logger.severe(
                  'Exception in removing flutter keychain entries :${e.toString()}');
            }
          });
        });
        try {
          await FlutterKeychain.remove(key: '@atsign');
        } on Exception catch (e) {
          _logger.severe(
              'Exception in removing flutter keychain entry for @atsign :${e.toString()}');
        }
      }
      // TODO: else condition
      // Question: what should be done if the flutter keychain values are not copied over completely?
      return atsignMapFromBS;
    }
    return atsignMap;
  }

  Future<String> getSecretFromKeychain(String atsign) async {
    String secret = '';
    try {
      assert(atsign.isNotEmpty);
      _storage = await getBiometricStorageFile(atsign + '_secret');
      var secretString = await _storage?.read();
      secret = secretString ?? '';
    } on Exception catch (e) {
      _logger.severe('Exception in getSecretFromKeychain :${e.toString()}');
    }
    return secret;
  }

  /// Use [getValue]
  @Deprecated("Use getValue")
  Future<String?> getPrivateKeyFromKeyChain(String atsign) async {
    String? pkamPrivateKey;
    try {
      assert(atsign.isNotEmpty);
      _storage = await getBiometricStorageFile(atsign + '_pkam_private_key');
      pkamPrivateKey = await _storage?.read();
    } on Exception catch (e) {
      _logger.severe('exception in getPrivateKeyFromKeyChain :${e.toString()}');
    }
    return pkamPrivateKey;
  }

  /// Use [getValue]
  @Deprecated("Use getValue")
  Future<String?> getPublicKeyFromKeyChain(String atsign) async {
    String? pkamPublicKey;
    try {
      assert(atsign.isNotEmpty);
      _storage = await getBiometricStorageFile(atsign + '_pkam_public_key');
      pkamPublicKey = await _storage?.read();
    } on Exception catch (e) {
      _logger.severe('exception in getPublicKeyFromKeyChain :${e.toString()}');
    }
    return pkamPublicKey;
  }

  Future<String?> getValue(String atsign, String key) async {
    String? value;
    try {
      assert(atsign.isNotEmpty);
      _storage = await getBiometricStorageFile(atsign + ':' + key);
      value = await _storage?.read();
    } on Exception catch (e) {
      _logger.severe(
          'Biometric storage - exception in get value for $key :${e.toString()}');
    }
    return value;
  }

  Future<String> putValue(String atsign, String key, String value) async {
    try {
      assert(atsign != '');
      _storage = await getBiometricStorageFile(atsign + ':' + key);
      await _storage?.write(value);
    } on Exception catch (e) {
      _logger.severe(
          'Biometric storage - exception in put value for $key :${e.toString()}');
    }
    return value;
  }

  Future<bool> storeCredentialToKeychain(String atSign,
      {String? secret, String? privateKey, String? publicKey}) async {
    var success = false;
    try {
      assert(atSign != '');
      atSign = atSign.trim().toLowerCase().replaceAll(' ', '');
      if (secret != null) {
        secret = secret.trim().toLowerCase().replaceAll(' ', '');
        _storage = await getBiometricStorageFile(atSign + ':' + keychainSecret);
        await _storage?.write(secret);
      }
      await _saveAtSignToKeychain(atSign);
      await storePkamKeysToKeychain(atSign,
          privateKey: privateKey, publicKey: publicKey);
      success = true;
    } on Exception catch (exception) {
      _logger.severe(
          'exception in storeCredentialToKeychain :${exception.toString()}');
    }
    return success;
  }

  Future<void> storePkamKeysToKeychain(String atsign,
      {String? privateKey, String? publicKey}) async {
    assert(atsign != '');
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    try {
      if (privateKey != null) {
        _storage = await getBiometricStorageFile(
            atsign + ':' + keychainPKAMPrivateKey);
        await _storage?.write(privateKey.toString());
      }
      if (publicKey != null) {
        _storage =
            await getBiometricStorageFile(atsign + ':' + keychainPKAMPublicKey);
        await _storage?.write(publicKey.toString());
      }
    } on Exception catch (exception) {
      _logger.severe(
          'exception in storeCredentialToKeychain :${exception.toString()}');
    }
  }

  List<int> _generatePersistenceSecret() {
    return Hive.generateSecureKey();
  }

  RSAKeypair generateKeyPair() {
    var rsaKeypair = RSAKeypair.fromRandom();
    return rsaKeypair;
  }

  Future<String?> getCramSecret(String atSign) async {
    return getSecretFromKeychain(atSign);
  }

  Future<String?> getPkamPrivateKey(String atSign) async {
    return getValue(atSign, keychainPKAMPrivateKey);
  }

  Future<String?> getPkamPublicKey(String atSign) async {
    return getValue(atSign, keychainPKAMPublicKey);
  }

  Future<String?> getEncryptionPrivateKey(String atSign) async {
    return getValue(atSign, keychainEncryptionPrivateKey);
  }

  Future<String?> getEncryptionPublicKey(String atSign) async {
    return getValue(atSign, keychainEncryptionPublicKey);
  }

  Future<String?> getSelfEncryptionAESKey(String atSign) async {
    return getValue(atSign, keychainSelfEncryptionKey);
  }

  Future<List<int>?> getKeyStoreSecret(String atSign) async {
    return getHiveSecretFromKeychain(atSign);
  }

  Future<String?> getAtSign() async {
    var atSignList = await getAtSignListFromKeychain();
    return atSignList == null ? atSignList as FutureOr<String?> : atSignList[0];
  }

  Future<void> _saveAtSignToKeychain(String atsign) async {
    Map<String, bool?> atsignMap = <String, bool>{};
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

  Future<void> _storeAtsign(Map<String, bool?> atsignMap) async {
    var value = jsonEncode(atsignMap);
    _storage = await getBiometricStorageFile('@atsign');
    await _storage?.write(value);
  }

  Future<Map<String, bool?>> _getAtSignMap(
      {bool useFlutterKeychain = false}) async {
    Map<String, bool?> atsignMap = <String, bool?>{};
    var atsignSecondMap = <String, bool>{};
    dynamic value;
    if (useFlutterKeychain) {
      value = await FlutterKeychain.get(key: '@atsign');
    } else {
      _storage = await getBiometricStorageFile('@atsign');
      value = await _storage?.read();
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
      if (useFlutterKeychain) {
        await _storeAtsign(atsignMap);
      }
    }
    return atsignMap;
  }

  Future<Map<String, bool?>> getAtsignsWithStatus() async {
    return await _getAtSignMap();
  }

  Future<bool> makeAtSignPrimary(String atsign) async {
    //check whether given atsign is an already active atsign
    var atsignMap = await _getAtSignMap();
    if (atsignMap.isEmpty || !atsignMap.containsKey(atsign)) {
      return false;
    }
    var activeAtsign =
        atsignMap.keys.firstWhere((key) => atsignMap[key] == true);
    if (activeAtsign != atsign) {
      atsignMap[activeAtsign] = false;
    }
    atsignMap[atsign] = true;
    var value = jsonEncode(atsignMap);
    _storage = await getBiometricStorageFile('@atsign');
    await _storage?.write(value);
    return true;
  }

  Future<void> deleteAtSignFromKeychain(String atsign) async {
    var atsignMap = await _getAtSignMap();
    if (!atsignMap.containsKey(atsign)) {
      return;
    }
    var isDeletedActiveAtsign = atsignMap[atsign];
    atsignMap.remove(atsign);
    if (atsignMap.isEmpty) {
      _storage = await getBiometricStorageFile('@atsign');
      await _storage?.delete();
      return;
    }
    if (isDeletedActiveAtsign!) {
      atsignMap[atsignMap.keys.first] = true;
    }
    var value = jsonEncode(atsignMap);
    _storage = await getBiometricStorageFile('@atsign');
    await _storage?.write(value);
  }

  Future<void> resetAtSignFromKeychain(String atsign) async {
    await deleteAtSignFromKeychain(atsign);
    _storage =
        await getBiometricStorageFile(atsign + ':' + keychainPKAMPrivateKey);
    await _storage?.delete();
    _storage =
        await getBiometricStorageFile(atsign + ':' + keychainPKAMPublicKey);
    await _storage?.delete();
    _storage = await getBiometricStorageFile(
        atsign + ':' + keychainEncryptionPrivateKey);
    await _storage?.delete();
    _storage = await getBiometricStorageFile(
        atsign + ':' + keychainEncryptionPublicKey);
    await _storage?.delete();
    _storage =
        await getBiometricStorageFile(atsign + ':' + keychainSelfEncryptionKey);
    await _storage?.delete();
  }

  Future<void> clearKeychainEntries() async {
    var atsignList = await getAtSignListFromKeychain();
    if (atsignList == null) {
      return;
    } else {
      await Future.forEach(atsignList, (String atsign) async {
        await resetAtSignFromKeychain(atsign);
      });
    }
  }
}
