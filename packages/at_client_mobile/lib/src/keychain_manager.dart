import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_utils/at_logger.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:crypton/crypton.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_constants.dart';

const String _kDefaultKeystoreAccount = '@atsigns';
const String enrollmentInfoKey = 'enrollmentInfo';

const int _kWindowSegmentDataLength =
    2560; //CREDENTIALA structure (wincred.h) - CRED_MAX_CREDENTIAL_BLOB_SIZE (5*512) bytes.

/// Service to manage keychain entries. This includes saving the
/// encryption keys and secret to keychain
class KeyChainManager {
  static final KeyChainManager _singleton = KeyChainManager._internal();

  static final _logger = AtSignLogger(' KeyChainManager ');

  KeyChainManager._internal();

  static bool isWindows = true;

  factory KeyChainManager.getInstance() {
    if (Platform.isWindows) {
      // ignore: undefined_method
      Win32BiometricStoragePlugin.registerWith();
    }
    return _singleton;
  }

  @visibleForTesting
  BiometricStorage biometricStorage = BiometricStorage();

  Future<AtClientData?> deleteAllData({
    bool useSharedStorage = false,
  }) async {
    try {
      final atKeysStore =
          await _getBiometricStorageFile(await getBiometricStoreNameAtKeys());
      await atKeysStore.delete();
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
    return null;
  }

  Future<AtClientData?> readAtClientData({
    bool useSharedStorage = false,
  }) async {
    String atKeysStoreName = await getBiometricStoreNameAtKeys();
    try {
      final value = await _readDataFromStore(
        biometricStoreName: atKeysStoreName,
      );
      final json = jsonDecode(value ?? '{}');
      if (json is Map<String, dynamic>) {
        return AtClientData.fromJson(json);
      }
    } catch (e, s) {
      _logger.severe('_getAtClientData failed with $e', e, s);
      print(s);
      _logger.severe('Removing data');
      await _writeDataToStore(biometricStoreName: atKeysStoreName, data: '');
    }
    return null;
  }

  Future<bool> enableUsingSharedStorage() async {
    return true;
  }

  Future<bool> disableUsingSharedStorage() async {
    return true;
  }

  Future<bool?> isUsingSharedStorage() async {
    return false;
  }

  /// Initial setup
  Future<void> initialSetup({required bool useSharedStorage}) async {}

  /// Function to get atsign's key with name
  Future<AtsignKey?> readAtsign({required String name}) async {
    final atSigns = await readAtsigns();
    if (atSigns.isEmpty) {
      return null;
    }
    for (int i = 0; i < atSigns.length; i++) {
      if (atSigns[i].atSign == name) {
        return atSigns[i];
      }
    }
    return null;
  }

  /// Function to get all atsign item in keychain
  Future<List<AtsignKey>> readAtsigns() async {
    final data = await readAtClientData();
    return data?.keys ?? [];
  }

  /// Function to add a new atsign to keychain
  Future<bool> storeAtSign({required AtsignKey atSign}) async {
    final atClientData = await readAtClientData();
    if (atClientData != null) {
      final atSigns = atClientData.keys;
      atSigns.removeWhere((element) => element.atSign == atSign.atSign);
      atSigns.add(atSign);
      await _saveAtClientData(data: atClientData);
      return true;
    } else {
      return false;
    }
  }

  /// Function to add new atsigns to keychain
  Future<bool> storeAtSigns({required List<AtsignKey> atSigns}) async {
    final atClientData = await readAtClientData();
    if (atClientData != null) {
      final oldAtSigns = atClientData.keys;
      //If have no account => make this account is default
      for (var atsign in atSigns) {
        oldAtSigns.removeWhere((element) => element.atSign == atsign.atSign);
        oldAtSigns.add(atsign);
      }
      final newAtClientData = atClientData.copyWith(keys: oldAtSigns);
      await _saveAtClientData(data: newAtClientData);
      return true;
    } else {
      return false;
    }
  }

  /// Function to get hive secret from keychain
  Future<List<int>> getHiveSecretFromKeychain(String atsign) async {
    assert(atsign.isNotEmpty);
    List<int> secretAsUint8List = [];
    try {
      var atsignItem = await readAtsign(name: atsign);
      var hiveSecretString = (await readAtsign(name: atsign))?.hiveSecret;
      if (hiveSecretString == null) {
        secretAsUint8List = _generatePersistenceSecret();
        hiveSecretString = String.fromCharCodes(secretAsUint8List);
        atsignItem = atsignItem?.copyWith(
          hiveSecret: hiveSecretString,
        );
        if (atsignItem != null) {
          storeAtSign(atSign: atsignItem);
        }
      } else {
        secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
      }
    } on Exception catch (exception) {
      _logger.severe(
          'exception in getHiveSecretFromKeychain : ${exception.toString()}');
    }

    return secretAsUint8List;
  }

  /// Fetches list of all the onboarded atsigns
  Future<List<String>> getAtSignListFromKeychain() async {
    final atsigns = await readAtsigns();
    return atsigns.map((e) => e.atSign).toList();
  }

  /// Function to get atsign secret from keychain
  Future<String> getSecretFromKeychain(String atsign) async {
    final atsigns = await readAtsign(name: atsign);
    return atsigns?.secret ?? '';
  }

  /// Use [readAtsign]
  @Deprecated("Use readAtsign function to get AtsignKey")
  Future<String?> getPrivateKeyFromKeyChain(String atsign) async {
    final atsigns = await readAtsign(name: atsign);
    return atsigns?.pkamPrivateKey;
  }

  /// Use [readAtsign]
  @Deprecated("Use readAtsign function to get AtsignKey")
  Future<String?> getPublicKeyFromKeyChain(String atsign) async {
    final atsigns = await readAtsign(name: atsign);
    return atsigns?.pkamPublicKey;
  }

  /// Function to save atsign and pkam keys passed to keychain
  Future<bool> storeCredentialToKeychain(String atSign,
      {String? secret, String? privateKey, String? publicKey}) async {
    try {
      final atClientData = await readAtClientData();
      final atsigns = atClientData?.keys ?? [];
      if (secret != null) {
        secret = secret.trim().toLowerCase().replaceAll(' ', '');
      }
      final index = atsigns.indexWhere((element) => element.atSign == atSign);
      if (index >= 0) {
        atsigns[index] = atsigns[index].copyWith(
          secret: secret,
          pkamPrivateKey: privateKey,
          pkamPublicKey: publicKey,
        );
      } else {
        atsigns.add(AtsignKey(atSign: atSign).copyWith(
          secret: secret,
          pkamPrivateKey: privateKey,
          pkamPublicKey: publicKey,
        ));
      }
      if (atClientData != null) {
        await _saveAtClientData(data: atClientData);
        return true;
      } else {
        return false;
      }
    } on Exception catch (exception) {
      _logger.severe(
          'exception in storeCredentialToKeychain :${exception.toString()}');
      return false;
    }
  }

  /// Function to save pkam keys for the atsign passed to keychain
  Future<bool> storePkamKeysToKeychain(String atsign,
      {String? privateKey, String? publicKey}) async {
    final atClientData = await readAtClientData();
    try {
      final atsigns = atClientData?.keys ?? [];
      final index = atsigns.indexWhere((element) => element.atSign == atsign);
      if (index >= 0) {
        atsigns[index] = atsigns[index].copyWith(
          pkamPrivateKey: privateKey,
          pkamPublicKey: publicKey,
        );
      } else {
        atsigns.add(AtsignKey(atSign: atsign).copyWith(
          pkamPrivateKey: privateKey,
          pkamPublicKey: publicKey,
        ));
      }
      atClientData?.keys = atsigns;
      if (atClientData != null) {
        await _saveAtClientData(data: atClientData);
        return true;
      } else {
        return false;
      }
    } catch (e, s) {
      print(e);
      print(s);
      return false;
    }
  }

  /// Function to generate a secure encryption key
  List<int> _generatePersistenceSecret() {
    return Hive.generateSecureKey();
  }

  /// Function to generate an RSA key pair
  RSAKeypair generateKeyPair() {
    var rsaKeypair = RSAKeypair.fromRandom();
    return rsaKeypair;
  }

  String generateAESKey() {
    return encrypt.AES(encrypt.Key.fromSecureRandom(32)).key.base64;
  }

  /// Function to get cram secret from keychain
  Future<String?> getCramSecret(String atSign) async {
    return getSecretFromKeychain(atSign);
  }

  /// Function to get pkam private key from keychain
  Future<String?> getPkamPrivateKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.pkamPrivateKey;
  }

  /// Function to get pkam public key from keychain
  Future<String?> getPkamPublicKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.pkamPublicKey;
  }

  /// Function to get encryption private key from keychain
  Future<String?> getEncryptionPrivateKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.encryptionPrivateKey;
  }

  /// Function to get encryption public key from keychain
  Future<String?> getEncryptionPublicKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.encryptionPublicKey;
  }

  /// Function to get self encryption key from keychain
  Future<String?> getSelfEncryptionAESKey(String atSign) async {
    final atsigns = await readAtsign(name: atSign);
    return atsigns?.selfEncryptionKey;
  }

  /// Function to get hive secret from keychain
  Future<List<int>?> getKeyStoreSecret(String atSign) async {
    return getHiveSecretFromKeychain(atSign);
  }

  /// Function to get default atsigns name from keychain
  Future<String?> getAtSign() async {
    final atClientData = await readAtClientData();
    final defaultAtsign = atClientData?.defaultAtsign;
    final atsignKeys = atClientData?.keys ?? [];
    for (var element in atsignKeys) {
      if (element.atSign == defaultAtsign) {
        return element.atSign;
      }
    }
    if (atsignKeys.isNotEmpty) return atsignKeys.first.atSign;
    return null;
  }

  /// Function to get Map of atsigns from keychain
  Future<Map<String, bool?>> getAtsignsWithStatus() async {
    return await _getAtSignMap();
  }

  /// Function to make the atsign passed as primary
  Future<bool> makeAtSignPrimary(String atsign) async {
    final atClientData = await readAtClientData();
    if (atClientData != null) {
      atClientData.defaultAtsign = atsign;
      await _saveAtClientData(data: atClientData);
      return true;
    } else {
      return false;
    }
  }

  /// Function to remove an atsign from list of atsigns and hence, from keychain
  Future<bool> deleteAtSignFromKeychain(String atsign) async {
    final atClientData = await readAtClientData();
    atClientData?.keys.removeWhere((element) => element.atSign == atsign);
    if (atClientData != null) {
      await _saveAtClientData(data: atClientData);
      return true;
    } else {
      return false;
    }
  }

  /// Function to delete all values related to the atsign passed from keychain
  Future<bool> resetAtSignFromKeychain(String atsign) async {
    AtClientData? atClientData;

    atClientData = await readAtClientData();

    atClientData?.keys.removeWhere((element) => element.atSign == atsign);

    if (atClientData != null) {
      await _saveAtClientData(data: atClientData);
      return true;
    } else {
      return false;
    }
  }

  /// This function is deprecated and will be removed in upcoming version. Use `getAtsignsWithStatus()` instead
  @Deprecated(
      "This function is deprecated and will be removed in upcoming version. Use `getAtsignsWithStatus()` instead")
  Future<Map<String, bool?>> checkForValuesInFlutterKeychain() async {
    return getAtsignsWithStatus();
  }

  /// Function to clear all entries from keychain
  Future<void> clearKeychainEntries() async {
    for (var element
        in (await KeyChainManager.getInstance().getAtSignListFromKeychain())) {
      await KeyChainManager.getInstance().deleteAtSignFromKeychain(element);
    }
  }

  /// This function is deprecated and will be removed in upcoming version
  @Deprecated(
      "This function is deprecated and will be removed in upcoming version")
  Future<BiometricStorageFile> getBiometricStorageFile(String key) async {
    return await _getBiometricStorageFile(key);
  }

  Future<BiometricStorageFile> _getBiometricStorageFile(String key) async {
    return await BiometricStorage().getStorage(key,
        options: StorageFileInitOptions(
          authenticationRequired: false,
        ));
  }

  /// Function to get value for the key passed from keychain
  @Deprecated(
      "This function is deprecated and will be removed in upcoming version")
  Future<String?> getValue(String atsign, String key) async {
    throw UnimplementedError();
  }

  /// Function to save value for the key passed to keychain
  @Deprecated(
      "This function is deprecated and will be removed in upcoming version")
  Future<String> putValue(String atsign, String key, String value) async {
    throw UnimplementedError();
  }

  String? _packageName;

  Future<String> _getPackageName() async {
    _packageName ??= (await PackageInfo.fromPlatform()).packageName;
    return _packageName!;
  }

  Future<BiometricStorageFile> getEnrollmentStorage(String atSign) async {
    final data = await biometricStorage.getStorage(
      '${atSign}_$enrollmentInfoKey',
      options: StorageFileInitOptions(
        authenticationRequired: false,
      ),
    );

    return data;
  }

  Future<String> getBiometricStoreNameAtKeys() async {
    String packageName = await _getPackageName();
    return '$_kDefaultKeystoreAccount:$packageName';
  }

  String getBiometricStoreNameEnrollment(String atSign) {
    return '${atSign}_$enrollmentInfoKey';
  }

  /// Function to save client data
  Future<bool> _saveAtClientData({
    required AtClientData data,
  }) async {
    try {
      final String atKeysStoreName = await getBiometricStoreNameAtKeys();
      final mapList = jsonEncode(data.toJson());
      await _writeDataToStore(
        biometricStoreName: atKeysStoreName,
        data: mapList,
      );
      return true;
    } catch (e, s) {
      _logger.info('_saveClientData', e, s);
      return false;
    }
  }

  /// Function to get Map of atsigns from keychain
  Future<Map<String, bool?>> _getAtSignMap() async {
    final atClientData = await readAtClientData();
    final atsigns = await readAtsigns();
    final result = <String, bool?>{};
    for (var element in atsigns) {
      result[element.atSign] = element.atSign == atClientData?.defaultAtsign;
    }
    return result;
  }

  writeToEnrollmentStore(String atSign, String data) async {
    await _writeDataToStore(
      biometricStoreName: getBiometricStoreNameEnrollment(atSign),
      data: data,
    );
  }

  Future<String?> readFromEnrollmentStore(String atSign) async {
    return await _readDataFromStore(
        biometricStoreName: getBiometricStoreNameEnrollment(atSign));
  }

  deleteEnrollmentStore(String atSign) async {
    final store = await getEnrollmentStorage(atSign);
    await store.delete();
  }

  void log(String s, bool logStackTrace) {
    _logger.info(s);
    if (!logStackTrace) {
      return;
    }
    List<String> st = StackTrace.current.toString().split('\n');
    for (int i = 0; i < 30 && i < st.length; i++) {
      if (st[i] == '<asynchronous suspension>') {
        continue;
      }
      _logger.info('    ${st[i]}');
    }
  }

  /// The function write String data to BiometricStorageFile
  /// If Platform is Windows, data will separated into segments before save. Because in Window, BiometricStorage limit the data length saved
  Future<void> _writeDataToStore({
    required String biometricStoreName,
    required String data,
  }) async {
    BiometricStorageFile store =
        await _getBiometricStorageFile(biometricStoreName);
    if (!isWindows) {
      await store.write(data);
    } else {
      log('WRITE: _writeDataToStore called', true);
      final dataList = _splitString(data, _kWindowSegmentDataLength);
      String segmentCountInfo = jsonEncode({'segmentCount': dataList.length});
      log('  => WRITE: Writing $segmentCountInfo to ${store.name}',
          false);
      await store.write(segmentCountInfo);

      for (int i = 0; i < dataList.length; i++) {
        final segmentStore =
            await _getBiometricStorageFile('${biometricStoreName}_segment_$i');
        log('  => WRITE: Writing segment $i length ${dataList[i].length} to ${segmentStore.name}',
            false);
        // log('  => WRITE: segmentValue was ${dataList[i]}', false);
        await segmentStore.write(dataList[i]);
      }
    }
  }

  /// The function read String data to BiometricStorageFile
  Future<String?> _readDataFromStore({
    required String biometricStoreName,
  }) async {
    final BiometricStorageFile store =
        await _getBiometricStorageFile(biometricStoreName);
    if (!isWindows) {
      return await store.read();
    } else {
      log('READ: _readDataFromStore called', true);
      String? storedData = await store.read();
      log('  => READ: Fetched $storedData from ${store.name}', false);
      if (storedData == null) {
        return null;
      }

      final int segmentCount;
      final String segmentPrefix;
      if (storedData.startsWith('{')) {
        final Map m = jsonDecode(storedData);
        segmentCount = m['segmentCount'];
        segmentPrefix = '${biometricStoreName}_segment';
        log(
            '  => READ: Got segmentCount $segmentCount'
                ', and inferred RELATIVE segmentPrefix $segmentPrefix,'
                ' from storedData $storedData',
            false);
      } else {
        // legacy
        segmentCount = int.tryParse(storedData) ?? 0;
        String packageName = await _getPackageName();
        segmentPrefix = '${packageName}_data';
        log(
            '  => READ: Got segmentCount $segmentCount'
                ', and inferred LEGACY, BUGGY segmentPrefix $segmentPrefix,'
                ' from storedData $storedData',
            false);
      }

      final results = <String>[];
      for (int i = 0; i < segmentCount; i++) {
        final segmentStore =
            await _getBiometricStorageFile('${segmentPrefix}_$i');
        String? segmentValue = await segmentStore.read();
        log(
            '  => READ: Fetched segment $i, length ${segmentValue?.length}'
            ' from ${segmentStore.name}',
            false);
        // log('  => READ: segmentValue was $segmentValue', false);
        results.add(segmentValue ?? '');
      }
      return _combineString(results);
    }
  }

  /// The function separated a String to a list of segment String
  /// Max length of segment is [segmentLength]
  List<String> _splitString(String text, int segmentLength) {
    int segmentCount = (text.length / segmentLength).ceil();
    final result = <String>[];
    for (int i = 0; i < segmentCount; i++) {
      if (i == segmentCount - 1) {
        result.add(text.substring(i * segmentLength, text.length));
      } else {
        result.add(text.substring(i * segmentLength, (i + 1) * segmentLength));
      }
    }
    return result;
  }

  /// The function combine list of String to String
  String? _combineString(List<String> texts) {
    if (texts.isEmpty) {
      return null;
    }
    return texts.join();
  }

  Future<Map<String, String>> getEncryptedKeys(String atsign) async {
    AtsignKey? atsignKeyData = await readAtsign(name: atsign);

    if (atsignKeyData == null) {
      throw AtClientException.message(
          "Failed to fetch the keys for the atsign: $atsign");
    }

    Map<String, String> encryptedAtKeysMap = <String, String>{};

    String encryptedPkamPublicKey = EncryptionUtil.encryptValue(
        atsignKeyData.pkamPublicKey!, atsignKeyData.selfEncryptionKey!);
    encryptedAtKeysMap[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE] =
        encryptedPkamPublicKey;

    String encryptedPkamPrivateKey = EncryptionUtil.encryptValue(
        atsignKeyData.pkamPrivateKey!, atsignKeyData.selfEncryptionKey!);
    encryptedAtKeysMap[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE] =
        encryptedPkamPrivateKey;

    String encryptedEncryptionPublicKey = EncryptionUtil.encryptValue(
        atsignKeyData.encryptionPublicKey!, atsignKeyData.selfEncryptionKey!);
    encryptedAtKeysMap[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE] =
        encryptedEncryptionPublicKey;

    String encryptedEncryptionPrivateKey = EncryptionUtil.encryptValue(
        atsignKeyData.encryptionPrivateKey!, atsignKeyData.selfEncryptionKey!);
    encryptedAtKeysMap[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE] =
        encryptedEncryptionPrivateKey;
    encryptedAtKeysMap[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE] =
        atsignKeyData.selfEncryptionKey!;
    // The atKeys file generated previous to APKAM feature will not have the
    // apkam_symmetric_key. Hence adding null check to prevent null-pointer exception.
    if (atsignKeyData.apkamSymmetricKey != null) {
      encryptedAtKeysMap[BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE] =
          atsignKeyData.apkamSymmetricKey!;
    }
    // The atKeys file generated previous to APKAM feature will not have the
    // enrollment-id. Hence adding null check to prevent null-pointer exception.
    if (atsignKeyData.enrollmentId != null) {
      encryptedAtKeysMap[BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE] =
          atsignKeyData.enrollmentId!;
    }
    return encryptedAtKeysMap;
  }
}
