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
      throw AtKeyException('AtsignKey not found in keychain for atSign: $atSign');
    }
    return atsignKey;
  }

  Future<List<AtKeys>> readAll() async {
    final atsigns = await keychainManager.getAllAtSigns();
    return atsigns;
  }

  @override
  Future<void> write(String atSign, AtKeys? atKeys) async {
    atKeys ??= await keychainManager.getAtSign(name: atSign) ?? generateKeyPairs(atSign: atSign);
    atKeys.metadata['atsign'] = atSign;
    atKeys.metadata['hiveSecret'] ??= String.fromCharCodes(Hive.generateSecureKey());
    await keychainManager.putAtSign(atKeys: atKeys);
  }

  Future<String?> readEnrollmentFromKeychain(String atsign) async {
    return await keychainManager.readFromEnrollmentStore(atsign);
  }

  Future<void> writeEnrollmentToKeychain(String atsign, String enrollmentId) async {
    await keychainManager.writeToEnrollmentStore(atsign, enrollmentId);
  }

  Future<void> deleteEnrollmentStore(String atSign) async {
    await keychainManager.deleteEnrollmentStore(atSign);
  }

  Future<List<String>> getAtsignsFromKeychain() async {
    List<AtKeys> atKeysList = await readAll();
    return atKeysList.map((e) => e.metadata['atsign'] as String).toList();
  }


  // Should we support legacy backup format?
  Future<Map<String, String>> getEncryptedKeys(String atsign) async {
    AtKeys? atsignKeyData = await keychainManager.getAtSign(name: atsign);

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
}