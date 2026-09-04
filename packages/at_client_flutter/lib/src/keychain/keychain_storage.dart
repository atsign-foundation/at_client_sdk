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
import 'package:package_info_plus/package_info_plus.dart';

import 'keychain_data.dart';

part 'keychain_store.dart';

final _maxEnrollmentAuthenticationRetryInHours = 48;
const int _kWindowSegmentDataLength =
    2560; //CREDENTIALA structure (wincred.h) - CRED_MAX_CREDENTIAL_BLOB_SIZE (5*512) bytes.

/// Service to manage keychain CRUD operations for Atsigns, enrollments and SPPs
class KeychainStorage {
  static final _logger = AtSignLogger('KeychainStorage');
  static bool isWindows = Platform.isWindows;
  @visibleForTesting
  late BiometricStorage biometricStorage;

  /// Create a [KeychainStorage] instance
  ///
  ///   [biometricStorage] - Optional [BiometricStorage] for mocking
  KeychainStorage({BiometricStorage? biometricStorage}) {
    if (isWindows) {
      // ignore: undefined_method
      Win32BiometricStoragePlugin.registerWith();
    }
    this.biometricStorage = biometricStorage ?? BiometricStorage();
  }

  /// Read all stored Atsign keys data from the keychain
  ///
  /// Returns [AtKeysData] containing all persisted [AtKeys] entries, or `null`
  /// if no key data has been stored yet
  Future<AtKeysData?> readAtKeysData() async {
    final data = await _readAtKeysDataRaw();
    if (data != null) {
      final json = jsonDecode(data);
      return AtKeysData.fromJson(json);
    }
    return null;
  }

  // Falls back to the pre-1.1.6 `_`-delimited store name and migrates it
  // forward, so upgrading doesn't orphan already-stored Atsign keys.
  Future<String?> _readAtKeysDataRaw() async {
    // 1. read `:` delimiter, if found, return that.
    final currentName = await AtKeysStore.getName();
    final data = await _read(keychainStoreName: currentName);
    if (data != null) {
      return data;
    }

    // -----------------------------
    // MIGRATION FLOW
    // people on < 1.1.6 used the `_` delimiter, when apps have historically always used `:`
    // this was a mistake, so >= 1.1.6 introduced the fix and migration path
    // >= 1.1.6 means `:` delimiter is now used for all future keys saved in keychain
    // apps who have no keys in `:` will look inside `_`, and if something there is found,
    // it will be duplicated and saved to `:`.
    // for the time being as of 1.1.6, we are not deleting keys in `_` just in case.
    // -----------------------------

    // 2. since nothing under `:` was found, let's use `_` delimiter
    // it's called "improper" because it used the wrong delimiter `_`
    final keychainStorageImproperName = await _getImproperAtKeysStoreName();
    String? improperDataString;
    try {
      improperDataString = await _read(
        keychainStoreName: keychainStorageImproperName,
      );
    } catch (e, s) {
      _logger.info('No legacy atKeysData found in keychain.', e, s);
      return null;
    }
    if (improperDataString == null) {
      return null;
    }

    _logger.info(
      'Migrating AtKeysData from legacy keychain store '
      '"$keychainStorageImproperName" to "$currentName"',
    );
    await _write(
      biometricStoreName: currentName,
      keychainData: AtKeysData.fromJson(jsonDecode(improperDataString)),
    );
    return improperDataString;
  }

  /// Get the stored keys for a specific Atsign
  ///
  ///   [atSign] - Atsign whose key material should be retrieved
  ///
  /// Returns [AtKeys] for the requested Atsign, or `null` if it is not present
  ///
  /// Throws [AtKeyException] if no Atsign data exists in the keychain
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

  /// Get all Atsigns currently stored in the keychain
  ///
  /// Returns a [List] of unique Atsign values
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

  /// Append a new [AtKeys] entry to the keychain
  ///
  ///   [keys] - [AtKeys] instance to persist
  ///
  /// Note: the Atsign must be included in the [AtKeys.metadata] field
  Future<void> appendAtKeysToKeychain({required AtKeys keys}) async {
    String? existingData;
    try {
      existingData = await _readAtKeysDataRaw();
    } catch (e) {
      _logger.info(
        'No existing atKeysData found in keychain. A new one will be created.',
      );
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

  /// Remove a stored Atsign entry from the keychain
  ///
  ///   [atSign] - Atsign whose persisted keys should be removed
  Future<void> removeAtsignFromKeychain(String atSign) async {
    try {
      final data = await _readAtKeysDataRaw();
      if (data != null) {
        final atKeysData = AtKeysData.fromJson(jsonDecode(data));
        atKeysData.keys.removeWhere(
          (element) => element.metadata['atsign'] == atSign,
        );
        await _write(
          biometricStoreName: (await AtKeysStore.getName()),
          keychainData: atKeysData,
        );
      } else {
        throw Exception('Unexpected data type found in keychain');
      }
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
  }

  /// Delete all persisted Atsign key data from the keychain, including any
  /// data still held under the legacy pre-1.1.6 `_` delimited store name.
  Future<void> deleteAllAtKeysData() async {
    try {
      final BiometricStorageFile biometricStore =
          await _getBiometricStorageFile(await AtKeysStore.getName());
      await biometricStore.delete();
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
    try {
      final BiometricStorageFile legacyBiometricStore =
          await _getBiometricStorageFile(await _getImproperAtKeysStoreName());
      await legacyBiometricStore.delete();
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
  }

  // Functions for EnrollmentStore CRUD operations
  /// Read stored enrollment data for an Atsign
  ///
  ///   [atSign] - Atsign whose enrollment data should be retrieved
  ///
  /// Returns [EnrollmentData] if present, otherwise `null`
  Future<EnrollmentData?> readEnrollmentData(String atSign) async {
    final String? data = await _read(
      keychainStoreName: EnrollmentStore(atSign).getName(),
    );
    if (data != null) {
      final Map<String, dynamic> jsonData = jsonDecode(data);
      return EnrollmentData.fromJson(jsonData);
    }
    return null;
  }

  /// Write enrollment data for an Atsign to the keychain
  ///
  ///   [atSign] - Atsign associated with the enrollment
  ///
  ///   [enrollmentData] - [EnrollmentData] to persist
  Future<void> writeEnrollmentData({
    required String atSign,
    required EnrollmentData enrollmentData,
  }) async {
    await _write(
      biometricStoreName: EnrollmentStore(atSign).getName(),
      keychainData: enrollmentData,
    );
  }

  /// Delete stored enrollment data for an Atsign
  ///
  ///   [atSign] - Atsign whose enrollment data should be removed
  Future<void> deleteEnrollmentData(String atSign) async {
    final BiometricStorageFile biometricStore = await _getBiometricStorageFile(
      EnrollmentStore(atSign).getName(),
    );
    await biometricStore.delete();
  }

  /// Validate whether stored enrollment data is still within the retry window
  ///
  ///   [atSign] - Atsign whose enrollment should be validated
  ///
  /// Returns `true` if the stored enrollment exists and is still valid.
  /// Returns `false` if no enrollment exists, validation fails, or the stored
  /// enrollment has expired. Expired enrollment data is removed automatically.
  Future<bool> validateEnrollment(String atSign) async {
    try {
      var data = await readEnrollmentData(atSign);
      if (data == null) {
        return false;
      }
      if (DateTime.now()
              .toUtc()
              .difference(
                DateTime.fromMillisecondsSinceEpoch(
                  data.enrollmentSubmissionTimeEpoch,
                ),
              )
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

  /// Save an SPP/OTP for an Atsign in the keychain
  ///
  ///   [atSign] - Atsign associated with the SPP
  ///
  ///   [otp] - [Otp] value to persist
  ///
  /// Appends the value to the existing SPP list after removing expired entries
  /// and any matching duplicate value
  Future<void> saveSpp(String atSign, Otp otp) async {
    final spp = SppData(value: otp.value, expiry: otp.expiry);

    SppListData sppListData;
    try {
      final existingData = await _read(
        keychainStoreName: SppStore(atSign).getName(),
      );
      if (existingData != null) {
        sppListData = SppListData.fromJson(jsonDecode(existingData));
      } else {
        sppListData = SppListData(spps: []);
      }
    } catch (e) {
      sppListData = SppListData(spps: []);
    }

    // Remove expired and the same value if it exists
    sppListData.spps.removeWhere(
      (element) => element.isExpired || element.value == spp.value,
    );
    sppListData.spps.add(spp);

    await _write(
      biometricStoreName: SppStore(atSign).getName(),
      keychainData: sppListData,
    );
    _logger.info('SPP saved to keychain');
  }

  /// Get all active SPPs stored for an Atsign
  ///
  ///   [atSign] - Atsign whose SPPs should be retrieved
  ///
  /// Returns a [List] of non-expired [SppData] values. Expired entries are
  /// removed from storage when encountered.
  Future<List<SppData>> getAllSpps(String atSign) async {
    try {
      final data = await _read(keychainStoreName: SppStore(atSign).getName());
      if (data == null) {
        return [];
      }
      SppListData sppListData = SppListData.fromJson(jsonDecode(data));

      // Filter out expired ones
      final activeSpps = sppListData.spps
          .where((spp) => !spp.isExpired)
          .toList();

      // If some were expired, update the store
      if (activeSpps.length != sppListData.spps.length) {
        if (activeSpps.isEmpty) {
          await deleteSppData(atSign);
        } else {
          await _write(
            biometricStoreName: SppStore(atSign).getName(),
            keychainData: SppListData(spps: activeSpps),
          );
        }
      }

      return activeSpps;
    } catch (e, st) {
      _logger.severe('Failed to get SPPs from keychain', e, st);
      return [];
    }
  }

  /// Get the active SPP for an Atsign
  ///
  ///   [atSign] - Atsign whose SPP should be retrieved
  ///
  /// Returns the most recently added non-expired [SppData], or `null` if none
  /// exist
  Future<SppData?> getActiveSpp(String atSign) async {
    final activeSpps = await getAllSpps(atSign);
    if (activeSpps.isEmpty) {
      return null;
    }
    return activeSpps.last;
  }

  /// Delete all stored SPP data for an Atsign
  ///
  ///   [atSign] - Atsign whose SPP data should be removed
  Future<void> deleteSppData(String atSign) async {
    try {
      final BiometricStorageFile biometricStore =
          await _getBiometricStorageFile(SppStore(atSign).getName());
      await biometricStore.delete();
    } catch (e) {
      _logger.warning('Failed to delete SPP data: $e');
    }
  }

  Future<String?> _read({required String keychainStoreName}) async {
    try {
      final BiometricStorageFile store = await _getBiometricStorageFile(
        keychainStoreName,
      );
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
          //log(
          //  '  => READ: Got segmentCount $segmentCount'
          //  ', and inferred RELATIVE segmentPrefix $segmentPrefix,'
          //  ' from storedData $storedData',
          //   false);
        } else {
          // legacy
          segmentCount = int.tryParse(storedData) ?? 0;
          String packageName = await getPackageName();
          segmentPrefix = '${packageName}_data';
          //log(
          //    '  => READ: Got segmentCount $segmentCount'
          //     ', and inferred LEGACY, BUGGY segmentPrefix $segmentPrefix,'
          //     ' from storedData $storedData',
          //     false);
        }
        final results = <String>[];
        for (int i = 0; i < segmentCount; i++) {
          final segmentStore = await _getBiometricStorageFile(
            '${segmentPrefix}_$i',
          );
          String? segmentValue = await segmentStore.read();
          log(
            '  => READ: Fetched segment $i, length ${segmentValue?.length}'
            ' from $segmentPrefix',
            false,
          );
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
        keychainData: EmptyKeychainData(),
      );
      rethrow;
    }
  }

  Future<void> _write({
    required String biometricStoreName,
    required KeychainData keychainData,
  }) async {
    final data = jsonEncode(keychainData.toJson());
    BiometricStorageFile store = await _getBiometricStorageFile(
      biometricStoreName,
    );
    if (!isWindows) {
      //log("WRITE: _writeDataToStore called", true);
      await store.write(data);
    } else {
      //log('WRITE: _writeDataToStore called', true);
      final dataList = _splitString(data, _kWindowSegmentDataLength);
      String segmentCountInfo = jsonEncode({'segmentCount': dataList.length});
      //log('  => WRITE: Writing $segmentCountInfo to ${store.name}', false);
      await store.write(segmentCountInfo);

      for (int i = 0; i < dataList.length; i++) {
        final segmentStore = await _getBiometricStorageFile(
          '${biometricStoreName}_segment_$i',
        );
        //log('  => WRITE: Writing segment $i length ${dataList[i].length} to ${segmentStore.name}',
        //    false);
        // log('  => WRITE: segmentValue was ${dataList[i]}', false);
        await segmentStore.write(dataList[i]);
      }
    }
  }

  Future<BiometricStorageFile> _getBiometricStorageFile(
    String storeName,
  ) async {
    return await biometricStorage.getStorage(
      storeName,
      options: StorageFileInitOptions(authenticationRequired: false),
    );
  }

  /// Split a string into fixed-size segments
  ///
  ///   [text] - Source string to split
  ///
  ///   [segmentLength] - Maximum length of each segment
  ///
  /// Returns a [List] of string segments
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

  /// Combine a list of string segments into a single string
  ///
  ///   [texts] - String segments to combine
  ///
  /// Returns the combined string, or `null` if the list is empty
  String? _combineString(List<String> texts) {
    if (texts.isEmpty) {
      return null;
    }
    return texts.join();
  }

  /// Write a message to the internal logger
  ///
  ///   [s] - Log message
  ///
  ///   [logStackTrace] - Whether to include the current stack trace
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
