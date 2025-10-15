import 'dart:convert';
import 'dart:io' show Platform;

import 'package:at_client_flutter/src/keychain/at_client_data.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:biometric_storage/biometric_storage.dart'
    show
        BiometricStorageFile,
        BiometricStorage,
        StorageFileInitOptions,
        Win32BiometricStoragePlugin;
import 'package:flutter/cupertino.dart';
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

const String _kDefaultKeystoreAccount = '@atsigns';
const int _kWindowSegmentDataLength =
    2560; //CREDENTIALA structure (wincred.h) - CRED_MAX_CREDENTIAL_BLOB_SIZE (5*512) bytes.
const String enrollmentInfoKey = 'enrollmentInfo';

class KeyChainStorage {
  static final _logger = AtSignLogger('KeyChainStorage');
  late PackageInfo _packageInfo;
  @visibleForTesting
  BiometricStorage biometricStorage = BiometricStorage();

  KeyChainStorage() {
    if (Platform.isWindows) {
      // ignore: undefined_method
      Win32BiometricStoragePlugin.registerWith();
    }
  }

  // Functions to interact with AtClientData stored in BiometricStorage

  /// Function to read client data
  /// Returns [AtClientData] if successful, null otherwise
  Future<AtClientData?> readAtClientData({
    bool useSharedStorage = false,
  }) async {
    try {
      final store = await _getAppStorage(useSharedStorage: useSharedStorage);
      final value = await readDataFromStore(
        store: store,
        useSharedStorage: useSharedStorage,
      );
      if (value == null) {
        return null;
      }
      final json = jsonDecode(value);
      if (json is Map<String, dynamic>) {
        return AtClientData.fromJson(json);
      }
    } catch (e, s) {
      _logger.info('readAtClientData', e, s);
      print(s);
      rethrow;
    }
    return null;
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

  // Functions to interact with the actual data stored in the BiometricStorage (keychain)

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
    var result = await store.read();
    return result;
  }

  Future<AtClientData?> deleteDataStore({
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
