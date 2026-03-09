import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_utils/at_logger.dart';
import 'package:biometric_storage/biometric_storage.dart';

/// Persists an active [Otp] (SPP) in the device's biometric keychain.
class SppKeychainData {
  static const _kStorageKey = 'spp';
  final AtSignLogger _logger = AtSignLogger('SppKeychainData');

  /// Saves [otp] to the keychain for [atSign].
  Future<void> save(String atSign, Otp otp) async {
    try {
      final storage = await _storage(atSign);
      await storage.write(jsonEncode(otp.toJson()));
      _logger.info('SPP saved to keychain');
    } catch (e, st) {
      _logger.warning('Failed to save SPP to keychain', e, st);
    }
  }

  /// Returns the active (non-expired) SPP for [atSign], or null if none or expired.
  Future<Otp?> getActive(String atSign) async {
    try {
      final storage = await _storage(atSign);
      final data = await storage.read();
      if (data == null) {
        _logger.info('No SPP found in keychain');
        return null;
      }
      final otp = Otp.fromJson(jsonDecode(data));
      if (otp.isExpired) {
        _logger.info('SPP found in keychain but has expired. Deleting.');
        await storage.delete();
        return null;
      }
      return otp;
    } catch (e, st) {
      _logger.severe('Failed to get SPP from keychain', e, st);
      return null;
    }
  }

  Future<BiometricStorageFile> _storage(String atSign) =>
      BiometricStorage().getStorage(
        '$atSign:$_kStorageKey',
        options: StorageFileInitOptions(authenticationRequired: false),
      );
}
