enum OnboardingStatus {
  ATSIGN_NOT_FOUND,
  PRIVATE_KEY_NOT_FOUND,
  ACTIVATE, //generate new keypair
  RESTORE, //restore backup file
  REUSE, //do nothing
  SYNC_TO_SERVER, // sync public encryption,pkam keys to server
  PKAM_PRIVATE_KEY_NOT_FOUND,
  PKAM_PUBLIC_KEY_NOT_FOUND,
  ENCRYPTION_PUBLIC_KEY_NOT_FOUND,
  ENCRYPTION_PRIVATE_KEY_NOT_FOUND,
  SELF_ENCRYPTION_KEY_NOT_FOUND
}
