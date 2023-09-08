import 'package:at_client_mobile/at_client_mobile.dart';

/// Holder for different encryption keys that will be stored in .atKeys file.
/// Apkam symmetric key, enrollmentId and defaultSelfEncryptionKey will be stored in unencrypted format in .atKeys file.
/// All other values will be encrypted before saving to .atKeys file.
class AtSecurityKeys {
  String? apkamPublicKey;
  String? apkamPrivateKey;
  String? defaultEncryptionPublicKey;
  String? defaultEncryptionPrivateKey;
  String? defaultSelfEncryptionKey;
  String? apkamSymmetricKey;
  String? enrollmentId;

  Map<String, String?> toMap() {
    var keysMap = <String, String?>{};
    keysMap[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE] =
        apkamPrivateKey;
    keysMap[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE] = apkamPublicKey;
    keysMap[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE] =
        defaultEncryptionPrivateKey;
    keysMap[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE] =
        defaultEncryptionPublicKey;
    keysMap[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE] =
        defaultSelfEncryptionKey;
    keysMap[BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE] =
        apkamSymmetricKey;
    keysMap[BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE] = enrollmentId;
    return keysMap;
  }
}
