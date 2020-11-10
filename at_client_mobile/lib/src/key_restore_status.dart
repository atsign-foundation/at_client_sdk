enum KeyRestoreStatus {
  ACTIVATE, //generate new keypair
  RESTORE, //restore backup file
  REUSE, //do nothing
  SYNC_TO_SERVER // sync public encryption,pkam keys to server
}
