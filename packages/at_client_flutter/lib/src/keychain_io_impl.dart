import 'package:at_auth/at_auth.dart' show KeyIOMixin, WrittenAtKeysIo, AtKeys;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/src/atsign_key.dart';
import 'package:at_utils/at_logger.dart';

class KeychainAtKeysIo extends WrittenAtKeysIo with KeyIOMixin {
  final KeyChainManager _keychainManager;
  final _logger = AtSignLogger('KeychainAtKeysIo');
  KeychainAtKeysIo(this._keychainManager);

  @override
  Future<AtsignKey> read(String atSign) async {
    final atsignKey = await _keychainManager.readAtsign(name: atSign);
    if (atsignKey == null) {
      throw AtKeyException('AtsignKey not found in keychain for atSign: $atSign');
    }
    return atsignKey;
  }

  Future<List<AtsignKey>> readAll() async {
    final atsigns = await _keychainManager.readAtsigns();
    return atsigns;
  }

  @override
  Future<void> write(String atSign, AtKeys atKeys) async {
    var atSignItem = await _keychainManager.readAtsign(name: atSign) ?? AtsignKey(atSign: atSign);
    atSignItem = atSignItem.copyWithAtKeys(atSign, atKeys);
    await _keychainManager.storeAtSign(atSign: atSignItem);
  }

  Future<void> writeToEnrollmentStore(String atSign, String data) async {
    final store = await _keychainManager.getEnrollmentStorage(atSign);
    await _keychainManager.writeDataToStore(store: store, data: data);
  }

  Future<String?> readFromEnrollmentStore(String atSign) async {
    final store = await _keychainManager.getEnrollmentStorage(atSign);
    return await _keychainManager.readDataFromStore(store: store);
  }

  Future<void> deleteEnrollmentStore(String atSign) async {
    final store = await _keychainManager.getEnrollmentStorage(atSign);
    await store.delete();
  }

  Future<Map<String, String>> getEncryptedKeys(String atsign) async {
    AtsignKey? atsignKeyData = await _keychainManager.readAtsign(name: atsign);

    if (atsignKeyData == null) {
      throw AtClientException.message("Failed to fetch the keys for the atsign: $atsign");
    }

    Map<String, String> encryptedAtKeysMap = <String, String>{};

    String encryptedPkamPublicKey = EncryptionUtil.encryptValue(
        atsignKeyData.apkamPublicKey!.toString(), atsignKeyData.defaultSelfEncryptionKey!.toString());
    encryptedAtKeysMap[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE] = encryptedPkamPublicKey;

    String encryptedPkamPrivateKey = EncryptionUtil.encryptValue(
        atsignKeyData.apkamPrivateKey!.toString(), atsignKeyData.defaultSelfEncryptionKey!.toString());
    encryptedAtKeysMap[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE] = encryptedPkamPrivateKey;

    String encryptedEncryptionPublicKey = EncryptionUtil.encryptValue(
        atsignKeyData.defaultEncryptionPublicKey!.toString(), atsignKeyData.defaultSelfEncryptionKey!.toString());
    encryptedAtKeysMap[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE] = encryptedEncryptionPublicKey;

    String encryptedEncryptionPrivateKey = EncryptionUtil.encryptValue(
        atsignKeyData.defaultEncryptionPrivateKey!.toString(), atsignKeyData.defaultSelfEncryptionKey!.toString());
    encryptedAtKeysMap[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE] = encryptedEncryptionPrivateKey;
    encryptedAtKeysMap[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE] =
        atsignKeyData.defaultSelfEncryptionKey.toString();
    // The atKeys file generated previous to APKAM feature will not have the
    // apkam_symmetric_key. Hence adding null check to prevent null-pointer exception.
    if (atsignKeyData.apkamSymmetricKey != null) {
      encryptedAtKeysMap[BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE] = atsignKeyData.apkamSymmetricKey.toString();
    }
    // The atKeys file generated previous to APKAM feature will not have the
    // enrollment-id. Hence adding null check to prevent null-pointer exception.
    if (atsignKeyData.enrollmentId != null) {
      encryptedAtKeysMap[BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE] = atsignKeyData.enrollmentId!;
    }
    return encryptedAtKeysMap;
  }

  /// Function to save keys for the atsign passed to keychain
  Future<bool> storeAtKeysToKeychain(String atsign, AtKeys atKeys) async {
    final internalAtClientData = await _keychainManager.readAtClientData(useSharedStorage: false);
    final useSharedStorage = internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData = await _keychainManager.readAtClientData(useSharedStorage: useSharedStorage);
    try {
      final atsigns = atClientData?.keys ?? [];
      final index = atsigns.indexWhere((element) => element.atSign == atsign);
      if (index >= 0) {
        atsigns[index] = atsigns[index].copyWithAtKeys(atsign, atKeys);
      } else {
        atsigns.add(AtsignKey(atSign: atsign).copyWithAtKeys(atsign, atKeys));
      }
      atClientData?.keys = atsigns;
      if (atClientData != null) {
        await _keychainManager.saveAtClientData(data: atClientData, useSharedStorage: useSharedStorage);
        return true;
      } else {
        return false;
      }
    } catch (e, s) {
      _logger.severe('exception in storeCredentialToKeychain :${e.toString()}');
      _logger.severe(s);
      return false;
    }
  }

  /// Function to clear all entries from keychain
  Future<void> deleteAllAtSignFromKeychain() async {
    var atsigns = await _keychainManager.readAtsigns();
    for (var element in atsigns.map((e) => e.atSign).toList()) {
      await _keychainManager.deleteAtSignFromKeychain(element);
    }
  }
}
