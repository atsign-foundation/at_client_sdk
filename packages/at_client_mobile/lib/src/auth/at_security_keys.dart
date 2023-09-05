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
}
