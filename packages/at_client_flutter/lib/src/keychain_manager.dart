import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_keychain/flutter_keychain.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:at_client_flutter/src/atsign_key.dart';

const String _kDefaultKeystoreAccount = '@atsigns';
const String enrollmentInfoKey = 'enrollmentInfo';

const int _kDataSchemeVersion = 2;
const int _kWindowSegmentDataLength =
    2560; //CREDENTIALA structure (wincred.h) - CRED_MAX_CREDENTIAL_BLOB_SIZE (5*512) bytes.

/// Service to manage keychain entries. This includes saving the
/// encryption keys and secret to keychain
class KeyChainManager {
  static final _logger = AtSignLogger('KeyChainUtil');
  late PackageInfo _packageInfo;

  KeyChainManager._internal();

  factory KeyChainManager() {
    if (Platform.isWindows) {
      // ignore: undefined_method
      Win32BiometricStoragePlugin.registerWith();
    }
    return KeyChainManager._internal();
  }

  @visibleForTesting
  BiometricStorage biometricStorage = BiometricStorage();

  Future<AtClientData?> deleteAllData({
    bool useSharedStorage = false,
  }) async {
    try {
      final store = await _getAppStorage(useSharedStorage: useSharedStorage);
      await store.delete();
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
    return null;
  }

  Future<AtClientData?> readAtClientData({
    bool useSharedStorage = false,
  }) async {
    try {
      final store = await _getAppStorage(useSharedStorage: useSharedStorage);
      final value = await readDataFromStore(
        store: store,
        useSharedStorage: useSharedStorage,
      );
      final json = jsonDecode(value ?? '{}');
      if (json is Map<String, dynamic>) {
        return AtClientData.fromJson(json);
      }
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
    return null;
  }

  /// Check app allow sharing atsign or not
  /// @returns 'null' if not define yet
  /// @returns 'true' if use sharing store
  /// @returns 'false' if use internal store
  Future<bool?> isUsingSharedStorage() async {
    final data = await readAtClientData(useSharedStorage: false);
    return data?.config?.useSharedStorage;
  }

  /// Initial setup
  Future<void> initialSetup({required bool useSharedStorage}) async {
    //Bring all key to internal and save in single key if need.
    await _migrateKeychainData();
    //
    if (useSharedStorage) {
      //Init shared storage if it not exiting
      final data = await readAtClientData(useSharedStorage: true);
      if (data == null) {
        saveAtClientData(
          data: AtClientData(
            config: AtClientDataConfig(
              schemaVersion: _kDataSchemeVersion,
            ),
            keys: [],
          ),
          useSharedStorage: useSharedStorage,
        );
      }
      await enableUsingSharedStorage();
    } else {
      await disableUsingSharedStorage();
    }
  }

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
    final atClientData = await readAtClientData(useSharedStorage: false);
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    final data = await readAtClientData(useSharedStorage: useSharedStorage);
    return data?.keys ?? [];
  }

  /// Function to add a new atsign to keychain
  Future<bool> storeAtSign({required AtsignKey atSign}) async {
    final internalAtClientData =
        await readAtClientData(useSharedStorage: false);
    final useSharedStorage =
        internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData =
        await readAtClientData(useSharedStorage: useSharedStorage);
    if (atClientData != null) {
      final atSigns = atClientData.keys;
      atSigns.removeWhere((element) => element.atSign == atSign.atSign);
      atSigns.add(atSign);
      await saveAtClientData(
          data: atClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  /// Function to add new atsigns to keychain
  Future<bool> storeAtSigns({required List<AtsignKey> atSigns}) async {
    final internalAtClientData =
        await readAtClientData(useSharedStorage: false);
    final useSharedStorage =
        internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData =
        await readAtClientData(useSharedStorage: useSharedStorage);
    if (atClientData != null) {
      final oldAtSigns = atClientData.keys;
      //If have no account => make this account is default
      for (var atsign in atSigns) {
        oldAtSigns.removeWhere((element) => element.atSign == atsign.atSign);
        oldAtSigns.add(atsign);
      }
      final newAtClientData = atClientData.copyWith(keys: oldAtSigns);
      await saveAtClientData(
          data: newAtClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  /// Function to get default atsigns name from keychain
  Future<String?> getAtSign() async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    final defaultAtsign = atClientData?.defaultAtsign;
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    final atsignKeys =
        (await readAtClientData(useSharedStorage: useSharedStorage))?.keys ??
            [];
    for (var element in atsignKeys) {
      if (element.atSign == defaultAtsign) {
        return element.atSign;
      }
    }
    if (atsignKeys.isNotEmpty) return atsignKeys.first.atSign;
    return null;
  }

  /// Function to make the atsign passed as primary
  Future<bool> makeAtSignPrimary(String atsign) async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    if (atClientData != null) {
      atClientData.defaultAtsign = atsign;
      await saveAtClientData(data: atClientData, useSharedStorage: false);
      return true;
    } else {
      return false;
    }
  }

  /// Function to remove an atsign from list of atsigns and hence, from keychain
  Future<bool> deleteAtSignFromKeychain(String atsign) async {
    final atClientData = await readAtClientData(useSharedStorage: false);
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    atClientData?.keys.removeWhere((element) => element.atSign == atsign);
    if (atClientData != null) {
      await saveAtClientData(
          data: atClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  /// Function to delete all values related to the atsign passed from keychain
  Future<bool> resetAtSignFromKeychain(String atsign) async {
    AtClientData? atClientData;

    final useSharedStorage = await isUsingSharedStorage();

    if (useSharedStorage == true) {
      final atClientDataShared = await readAtClientData(useSharedStorage: true);

      atClientDataShared?.keys
          .removeWhere((element) => element.atSign == atsign);

      atClientData = await readAtClientData(useSharedStorage: false);

      atClientData?.keys.removeWhere((element) => element.atSign == atsign);

      if (atClientData != null && atClientDataShared != null) {
        await saveAtClientData(data: atClientData, useSharedStorage: false);

        await saveAtClientData(
            data: atClientDataShared, useSharedStorage: true);

        return true;
      } else {
        return false;
      }
    } else {
      atClientData = await readAtClientData(useSharedStorage: false);

      atClientData?.keys.removeWhere((element) => element.atSign == atsign);

      if (atClientData != null) {
        await saveAtClientData(data: atClientData, useSharedStorage: false);
        return true;
      } else {
        return false;
      }
    }
  }

  Future<BiometricStorageFile> _getAppStorage({
    bool useSharedStorage = false,
  }) async {
    String packageName = '';
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      packageName = _packageInfo.packageName;
    } catch (e, s) {
      _logger.warning('Get PackageInfo', e, s);
    }

    final data = await biometricStorage.getStorage(
      useSharedStorage
          ? '$_kDefaultKeystoreAccount:shared'
          : '$_kDefaultKeystoreAccount:$packageName',
      options: StorageFileInitOptions(
        authenticationRequired: false,
      ),
    );

    return data;
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

  /// Function to save client data
  Future<bool> saveAtClientData({
    required AtClientData data,
    required bool useSharedStorage,
  }) async {
    try {
      final store = await _getAppStorage(useSharedStorage: useSharedStorage);
      final mapList = jsonEncode(data.toJson());
      await writeDataToStore(
        store: store,
        data: mapList,
        useSharedStorage: useSharedStorage,
      );
      return true;
    } catch (e, s) {
      _logger.info('_saveClientData', e, s);
      return false;
    }
  }

  /// The function write String data to BiometricStorageFile
  /// If Platform is Windows, data will separated into segments before save. Because in Window, BiometricStorage limit the data length saved
  Future<void> writeDataToStore({
    required BiometricStorageFile store,
    required String data,
    bool useSharedStorage = false,
  }) async {
    if (Platform.isWindows) {
      final dataList = _splitString(data, _kWindowSegmentDataLength);
      await store.write(dataList.length.toString());
      _packageInfo = await PackageInfo.fromPlatform();
      final packageName = _packageInfo.packageName;

      for (int i = 0; i < dataList.length; i++) {
        final dataStore = await BiometricStorage().getStorage(
          useSharedStorage ? 'shared_data_$i' : '${packageName}_data_$i',
          options: StorageFileInitOptions(
            authenticationRequired: false,
          ),
        );
        await dataStore.write(dataList[i]);
      }
    } else {
      await store.write(data);
    }
  }

  /// The function read String data to BiometricStorageFile
  Future<String?> readDataFromStore({
    required BiometricStorageFile store,
    bool useSharedStorage = false,
  }) async {
    if (Platform.isWindows) {
      var whatsindex = await store.read();
      final segmentCount = int.tryParse(whatsindex ?? '0') ?? 0;
      _packageInfo = await PackageInfo.fromPlatform();
      final packageName = _packageInfo.packageName;
      final results = <String>[];
      for (int i = 0; i < segmentCount; i++) {
        final dataStore = await biometricStorage.getStorage(
          useSharedStorage ? 'shared_data_$i' : '${packageName}_data_$i',
          options: StorageFileInitOptions(
            authenticationRequired: false,
          ),
        );
        results.add(await dataStore.read() ?? '');
      }
      return _combineString(results);
    }
    return await store.read();
  }

  /// Change atsign data to internal store
  Future<bool> disableUsingSharedStorage() async {
    final data = await readAtClientData(useSharedStorage: false);
    if (data != null) {
      if (data.config?.useSharedStorage == false) {
        return false;
      }
      final newConfig = data.config?.copyWith(useSharedStorage: false);
      var newData = data.copyWith(config: newConfig);
      await saveAtClientData(data: newData, useSharedStorage: false);
      final sharedAtsigns =
          (await readAtClientData(useSharedStorage: true))?.keys ?? [];
      final result = await storeAtSigns(atSigns: sharedAtsigns);
      return result;
    }
    return false;
  }

  /// Change atsign data to internal store
  Future<bool> enableUsingSharedStorage() async {
    //Init shared storage if it not exiting
    final sharedData = await readAtClientData(useSharedStorage: true);
    if (sharedData == null) {
      await saveAtClientData(
        data: AtClientData(
          config: AtClientDataConfig(
            schemaVersion: _kDataSchemeVersion,
          ),
          keys: [],
        ),
        useSharedStorage: true,
      );
    }
    //
    final data = await readAtClientData(useSharedStorage: false);
    if (data != null) {
      final newConfig = data.config?.copyWith(useSharedStorage: true);
      var newData = data.copyWith(config: newConfig);
      await saveAtClientData(data: newData, useSharedStorage: false);
      final result = await storeAtSigns(atSigns: data.keys);
      if (result) {
        newData = newData.copyWith(keys: []);
        await saveAtClientData(data: newData, useSharedStorage: false);
      }
      return result;
    }
    return false;
  }

  /// Function to group all keys saved in old version app to new data
  Future<void> _migrateKeychainData() async {
    //Check if contain new key format
    final clientData = await readAtClientData(useSharedStorage: false);
    final schemaVersion = clientData?.config?.schemaVersion ?? 0;
    final useSharedStorage = clientData?.config?.useSharedStorage ?? false;
    if (schemaVersion == _kDataSchemeVersion) {
      //No need migrate
      return;
    }
    AtClientData migratedData = AtClientData(
      config: AtClientDataConfig(
        schemaVersion: _kDataSchemeVersion,
        useSharedStorage: useSharedStorage,
      ),
      keys: [],
    );
    //Migrate data from version 0 => 1
    if (schemaVersion < 1) {
      //Read old key
      final List<AtsignKey> newAtSignKeys = [];
      try {
        Map<String, dynamic>? keysFromBiometric;
        Map<String, dynamic>? keysFromKeychain;
        try {
          final data =
              await (await BiometricStorage().getStorage('@atsign')).read();
          keysFromBiometric = jsonDecode(data ?? '{}');
        } catch (e, s) {
          _logger.warning('Read keys from BiometricStorage', e, s);
        }
        try {
          final data = await FlutterKeychain.get(key: '@atsign');
          keysFromKeychain = jsonDecode(data ?? '{}');
        } catch (e, s) {
          _logger.warning('Read keys from FlutterKeychain', e, s);
        }
        if ((keysFromBiometric ?? <String, dynamic>{}).isNotEmpty) {
          for (var entry in keysFromBiometric!.entries) {
            final key = entry.key;
            final value = entry.value;
            if (value == true) {
              migratedData.defaultAtsign = key;
            }
            final String? pkamPublicKey = await (await BiometricStorage()
                    .getStorage('$key:_pkam_public_key'))
                .read();
            final String? pkamPrivateKey = await (await BiometricStorage()
                    .getStorage('$key:_pkam_private_key'))
                .read();
            final String? encryptionPublicKey = await (await BiometricStorage()
                    .getStorage('$key:_encryption_public_key'))
                .read();
            final String? encryptionPrivateKey = await (await BiometricStorage()
                    .getStorage('$key:_encryption_private_key'))
                .read();
            final String? selfEncryptionKey =
                await (await BiometricStorage().getStorage('$key:_aesKey'))
                    .read();
            final String? hiveSecret =
                await (await BiometricStorage().getStorage('$key:_hive_secret'))
                    .read();
            final String? secret =
                await (await BiometricStorage().getStorage('$key:_secret'))
                    .read();
            final newAtSignKey = AtsignKey(
              atSign: key,
              apkamPublicKey: AtBytes.fromString(pkamPublicKey!),
              apkamPrivateKey: AtBytes.fromString(pkamPrivateKey!),
              defaultEncryptionPublicKey:
                  AtBytes.fromString(encryptionPublicKey!),
              defaultEncryptionPrivateKey:
                  AtBytes.fromString(encryptionPrivateKey!),
              defaultSelfEncryptionKey: AtBytes.fromString(selfEncryptionKey!),
              hiveSecret: hiveSecret!,
              cramKey: secret,
            );
            newAtSignKeys.add(newAtSignKey);
          }
        } else if ((keysFromKeychain ?? <String, dynamic>{}).isNotEmpty) {
          //Read data and migrate from 'FlutterKeychain'
          for (var entry in keysFromKeychain!.entries) {
            final key = entry.key;
            final value = entry.value;
            if (value == true) {
              migratedData.defaultAtsign = key;
            }
            final String? pkamPublicKey =
                await FlutterKeychain.get(key: '$key:_pkam_public_key');
            final String? pkamPrivateKey =
                await FlutterKeychain.get(key: '$key:_pkam_private_key');
            final String? encryptionPublicKey =
                await FlutterKeychain.get(key: '$key:_encryption_public_key');
            final String? encryptionPrivateKey =
                await FlutterKeychain.get(key: '$key:_encryption_private_key');
            final String? selfEncryptionKey =
                await FlutterKeychain.get(key: '$key:_aesKey');
            final String? hiveSecret =
                await FlutterKeychain.get(key: '$key:_hive_secret');
            final String? secret =
                await FlutterKeychain.get(key: '$key:_secret');
            final newAtSignKey = AtsignKey(
              atSign: key,
              apkamPublicKey: AtBytes.fromString(pkamPublicKey!),
              apkamPrivateKey: AtBytes.fromString(pkamPrivateKey!),
              defaultEncryptionPublicKey:
                  AtBytes.fromString(encryptionPublicKey!),
              defaultEncryptionPrivateKey:
                  AtBytes.fromString(encryptionPrivateKey!),
              defaultSelfEncryptionKey: AtBytes.fromString(selfEncryptionKey!),
              hiveSecret: hiveSecret,
              cramKey: secret,
            );
            newAtSignKeys.add(newAtSignKey);
          }
        }
        migratedData = migratedData.copyWith(keys: newAtSignKeys);
      } catch (e, s) {
        _logger.warning('Migrate Keychain Data', e, s);
      }
    }
    //Migrate data from version 1 => 2
    if (schemaVersion < 2) {
      //For next update data structure
    }
    await saveAtClientData(data: migratedData, useSharedStorage: false);
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
}
