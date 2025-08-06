enum KeyType {
  selfKey,
  sharedKey,
  publicKey,
  privateKey,
  cachedPublicKey,
  cachedSharedKey,
  reservedKey,
  localKey,
  invalidKey
}

enum ReservedKey {
  encryptionSharedKey,
  encryptionPublicKey,
  encryptionPrivateKey,
  pkamPublicKey,
  signingPrivateKey,
  signingPublicKey,
  nonReservedKey
}
