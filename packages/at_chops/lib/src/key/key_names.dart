class KeyNames {
  static const String selfEncryptionKey = 'selfEncryptionKey';
  static const String apkamSymmetricKey = 'apkamSymmetricKey';
  static const String rsa2048EncKey = 'rsa2048EncKey';
  static const String rsa4096EncKey = 'rsa4096EncKey';
  static const String defaultEncryptionPublicKey = 'defaultEncyptionPublicKey';
  static const String defaultEncryptionPrivateKey =
      'defaultEncyptionPrivateKey';

  static String lookup(String name) {
    switch (name) {
      case selfEncryptionKey:
        return selfEncryptionKey;
      case apkamSymmetricKey:
        return apkamSymmetricKey;
      case rsa2048EncKey:
        return rsa2048EncKey;
      case rsa4096EncKey:
        return rsa4096EncKey;
      case defaultEncryptionPublicKey:
        return defaultEncryptionPublicKey;
      case defaultEncryptionPrivateKey:
        return defaultEncryptionPrivateKey;
      default:
        throw ArgumentError('no such keyname');
    }
  }
}
