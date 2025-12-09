import 'dart:convert';
import 'dart:io' show Platform;

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:biometric_storage/biometric_storage.dart'
    show
        BiometricStorageFile,
        BiometricStorage,
        StorageFileInitOptions,
        Win32BiometricStoragePlugin;
import 'package:flutter/cupertino.dart';

import 'keychain_data.dart';
import 'keychain_store.dart';

final _maxEnrollmentAuthenticationRetryInHours = 48;
const int _kWindowSegmentDataLength =
    2560; //CREDENTIALA structure (wincred.h) - CRED_MAX_CREDENTIAL_BLOB_SIZE (5*512) bytes.

/// Service to manage keychain CRUD operations for atsigns & enrollments
class KeychainStorage {
  static final _logger = AtSignLogger('KeychainStorage');
  static bool isWindows = Platform.isWindows;
  @visibleForTesting
  late BiometricStorage biometricStorage;

  KeychainStorage({BiometricStorage? biometricStorage}) {
    if (isWindows) {
      // ignore: undefined_method
      Win32BiometricStoragePlugin.registerWith();
    }
    this.biometricStorage = biometricStorage ?? BiometricStorage();
  }

  // All exposed methods for keychain storage operations

  // Functions for AtKeysData CRUD operations

  /// Function to read AtKeysData from keychain
  Future<AtKeysData?> readAtKeysData() async {
    final data = await _read(keychainStoreName: (await AtKeysStore.getName()));
    if (data != null) {
      final json = jsonDecode(data);
      return AtKeysData.fromJson(json);
    }
    return null;
  }

  Future<AtKeys?> getAtsign(String atSign) async {
    final atKeysData = await readAtKeysData();
    if (atKeysData == null) {
      throw AtKeyException('No atsign found in keychain');
    }
    for (int i = 0; i < atKeysData.keys.length; i++) {
      // Check for both 'atsign' and legacy 'name' keys in metadata
      if (atKeysData.keys[i].metadata.containsKey('atsign')) {
        if (atKeysData.keys[i].metadata['atsign'] == atSign) {
          return atKeysData.keys[i];
        }
      } else if (atKeysData.keys[i].metadata['name'] == atSign) {
        return atKeysData.keys[i];
      }
    }
    return null;
  }

  Future<List<String>> getAllAtsigns() async {
    final atKeysData = await readAtKeysData();
    if (atKeysData == null) {
      return [];
    }
    final atSigns = <String>{};
    for (int i = 0; i < atKeysData.keys.length; i++) {
      // Check for both 'atsign' and legacy 'name' keys in metadata
      if (atKeysData.keys[i].metadata.containsKey('atsign')) {
        atSigns.add(atKeysData.keys[i].metadata['atsign']);
      } else if (atKeysData.keys[i].metadata['name']) {
        atSigns.add(atKeysData.keys[i].metadata['name']);
      }
    }
    return atSigns.toList();
  }

  Future<void> appendAtKeysToKeychain({
    required AtKeys keys,
  }) async {
    String? existingData;
    try {
      existingData =
          await _read(keychainStoreName: (await AtKeysStore.getName()));
    } catch (e) {
      _logger.info(
          'No existing atKeysData found in keychain. A new one will be created.');
    }
    if (existingData == null) {
      final atKeysData = AtKeysData(keys: [keys]);
      await _write(
        biometricStoreName: (await AtKeysStore.getName()),
        keychainData: atKeysData,
      );
      return;
    }
    final atKeysData = AtKeysData.fromJson(jsonDecode(existingData));
    atKeysData.keys.add(keys);
    await _write(
      biometricStoreName: (await AtKeysStore.getName()),
      keychainData: atKeysData,
    );
  }

  Future<void> removeAtsignFromKeychain(String atSign) async {
    try {
      final data =
          await _read(keychainStoreName: (await AtKeysStore.getName()));
      if (data != null) {
        final atKeysData = AtKeysData.fromJson(jsonDecode(data));
        atKeysData.keys
            .removeWhere((element) => element.metadata['atsign'] == atSign);
        await _write(
            biometricStoreName: (await AtKeysStore.getName()),
            keychainData: atKeysData);
      } else {
        throw Exception('Unexpected data type found in keychain');
      }
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
  }

  Future<void> deleteAllAtKeysData() async {
    try {
      final BiometricStorageFile biometricStore =
          await _getBiometricStorageFile(await AtKeysStore.getName());
      await biometricStore.delete();
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
  }

  // Functions for EnrollmentStore CRUD operations
  Future<EnrollmentData?> readEnrollmentData(String atSign) async {
    final String? data =
        await _read(keychainStoreName: EnrollmentStore(atSign).getName());
    if (data != null) {
      final Map<String, dynamic> jsonData = jsonDecode(data);
      return EnrollmentData.fromJson(jsonData);
    }
    return null;
  }

  Future<void> writeEnrollmentData({
    required String atSign,
    required EnrollmentData enrollmentData,
  }) async {
    await _write(
      biometricStoreName: EnrollmentStore(atSign).getName(),
      keychainData: enrollmentData,
    );
  }

  Future<void> deleteEnrollmentData(String atSign) async {
    final BiometricStorageFile biometricStore =
        await _getBiometricStorageFile(EnrollmentStore(atSign).getName());
    await biometricStore.delete();
  }

  /// Validates if the enrollment is still valid based on the submission time.
  Future<bool> validateEnrollment(String atSign) async {
    try {
      var data = await readEnrollmentData(atSign);
      if (data == null) {
        return false;
      }
      if (DateTime.now()
              .toUtc()
              .difference(DateTime.fromMillisecondsSinceEpoch(
                  data.enrollmentSubmissionTimeEpoch))
              .inHours >=
          _maxEnrollmentAuthenticationRetryInHours) {
        await deleteEnrollmentData(atSign);
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> _read({
    required String keychainStoreName,
  }) async {
    try {
      final BiometricStorageFile store =
          await _getBiometricStorageFile(keychainStoreName);
      String? value;
      if (!isWindows) {
        value = await store.read();
        return value;
      } else {
        // log('READ: _readDataFromStore called', true);
        String? storedData = await store.read();
        log('  => READ: Fetched $storedData from $keychainStoreName', false);
        if (storedData == null || storedData.isEmpty) {
          return null;
        }

        final int segmentCount;
        final String segmentPrefix;
        if (storedData.startsWith('{')) {
          final Map m = jsonDecode(storedData);
          segmentCount = m['segmentCount'];
          segmentPrefix = '${keychainStoreName}_segment';
          log(
              '  => READ: Got segmentCount $segmentCount'
              ', and inferred RELATIVE segmentPrefix $segmentPrefix,'
              ' from storedData $storedData',
              false);
        } else {
          // legacy
          segmentCount = int.tryParse(storedData) ?? 0;
          String packageName = await getPackageName();
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
              ' from $segmentPrefix',
              false);
          // log('  => READ: segmentValue was $segmentValue', false);
          results.add(segmentValue ?? '');
        }
        value = _combineString(results);

        return value;
      }
    } catch (e, s) {
      _logger.severe('_read failed with $e', e, s);
      print(s);
      _logger.severe('Removing data');
      await _write(
          biometricStoreName: keychainStoreName,
          keychainData: EmptyKeychainData());
      rethrow;
    }
    return null;
  }

  Future<void> _write({
    required String biometricStoreName,
    required KeychainData keychainData,
  }) async {
    final data = jsonEncode(keychainData.toJson());
    BiometricStorageFile store =
        await _getBiometricStorageFile(biometricStoreName);
    if (!isWindows) {
      log("WRITE: _writeDataToStore called", true);
      await store.write(data);
    } else {
      log('WRITE: _writeDataToStore called', true);
      final dataList = _splitString(data, _kWindowSegmentDataLength);
      String segmentCountInfo = jsonEncode({'segmentCount': dataList.length});
      log('  => WRITE: Writing $segmentCountInfo to ${store.name}', false);
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

  Future<BiometricStorageFile> _getBiometricStorageFile(
      String storeName) async {
    return await biometricStorage.getStorage(storeName,
        options: StorageFileInitOptions(
          authenticationRequired: false,
        ));
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
}
