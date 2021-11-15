enum OnboardingStatus {
  atSignNotFound,
  privateKeyNotFound,
  activate, //generate new keypair
  restore, //restore backup file
  reuse, //do nothing
  syncToServer, // sync public encryption,pkam keys to server
  pkamPrivateKeyNotFound,
  pkamPublicKeyNotFound,
  encryptionPublicKeyNotFound,
  encryptionPrivateKeyNotFound,
  selfEncryptionKeyNotFound
}
