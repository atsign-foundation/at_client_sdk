class BackupKeyConstants {
  // ignore_for_file: constant_identifier_names
  static const String PKAM_PUBLIC_KEY_FROM_KEY_FILE = 'aesPkamPublicKey';
  static const String PKAM_PRIVATE_KEY_FROM_KEY_FILE = 'aesPkamPrivateKey';
  static const String ENCRYPTION_PUBLIC_KEY_FROM_FILE = 'aesEncryptPublicKey';
  static const String ENCRYPTION_PRIVATE_KEY_FROM_FILE = 'aesEncryptPrivateKey';
  static const String SELF_ENCRYPTION_KEY_FROM_FILE = 'selfEncryptionKey';
  static const String APKAM_SYMMETRIC_KEY_FROM_FILE = 'apkamSymmetricKey';
  static const String APKAM_ENROLLMENT_ID_FROM_FILE = 'enrollmentId';
}

const String keychainSecret = '_secret';
const String keychainPKAMPrivateKey = '_pkam_private_key';
const String keychainPKAMPublicKey = '_pkam_public_key';
const String keychainEncryptionPrivateKey = '_encryption_private_key';
const String keychainEncryptionPublicKey = '_encryption_public_key';
const String keychainSelfEncryptionKey = '_aesKey';

const List<String> keychainKeys = [
  keychainSecret,
  keychainPKAMPrivateKey,
  keychainPKAMPublicKey,
  keychainEncryptionPrivateKey,
  keychainEncryptionPublicKey,
  keychainSelfEncryptionKey
];
