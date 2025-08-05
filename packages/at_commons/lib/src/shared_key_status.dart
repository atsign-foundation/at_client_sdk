enum SharedKeyStatus {
  localUpdated,
  remoteUpdated,
  sharedWithNotified,
  sharedWithLookedUp,
  sharedWithRead
}

String getSharedKeyName(SharedKeyStatus d) => '$d'.split('.').last;
