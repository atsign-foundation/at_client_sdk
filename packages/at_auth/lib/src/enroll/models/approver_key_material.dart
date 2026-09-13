/// What an approver brings to an approval, and all of it: the atSign's
/// encryption private key, which unwraps the APKAM symmetric key a legacy
/// enrollee RSA-wrapped to the atSign, and its self-encryption key, one of the
/// two secrets the approval seals for the enrollee under that symmetric key.
///
/// Both are the base64 strings a keyfile or a keystore holds. Neither is
/// authentication, so neither belongs on a network object.
typedef ApproverKeyMaterial = ({
  String encryptionPrivateKey,
  String selfEncryptionKey,
});
