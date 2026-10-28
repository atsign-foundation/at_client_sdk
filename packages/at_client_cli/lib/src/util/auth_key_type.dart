class AuthKeyType {
  static const String aesEncryptedPkamPublicKey = 'aesPkamPublicKey';
  static const String aesEncryptedPkamPrivateKey = 'aesPkamPrivateKey';
  static const String aesEncryptedEncryptionPublicKey = 'aesEncryptPublicKey';
  static const String aesEncryptedEncryptionPrivateKey = 'aesEncryptPrivateKey';

  static const String unencryptedPkamPublicKey = 'pkamPublicKey';
  static const String unencryptedPkamPrivateKey = 'pkamPrivateKey';
  static const String unencryptedEncryptionPublicKey = 'encryptPublicKey';
  static const String unencryptedEncryptionPrivateKey = 'encryptPrivateKey';

  static const String selfEncryptionKey = 'selfEncryptionKey';
  static const String apkamSymmetricKey = 'apkamSymmetricKey';

  // legacy names preserved for backwards compatibility
  @Deprecated("Use aesEncryptedPkamPublicKey instead")
  static String get pkamPublicKey => aesEncryptedPkamPublicKey;
  @Deprecated("Use aesEncryptedPkamPrivateKey instead")
  static String get pkamPrivateKey => aesEncryptedPkamPrivateKey;
  @Deprecated("Use aesEncryptedEncryptionPublicKey instead")
  static String get encryptionPublicKey => aesEncryptedEncryptionPublicKey;
  @Deprecated("Use aesEncryptedEncryptionPrivateKey instead")
  static String get encryptionPrivateKey => aesEncryptedEncryptionPrivateKey;
}
