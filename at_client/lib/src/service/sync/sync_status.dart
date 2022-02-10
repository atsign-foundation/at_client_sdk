///Enum to represent the sync status
enum SyncStatus { notStarted, success, failure }

class SyncProgress {
  SyncStatus? syncStatus;
  bool isInitialSync = false;
  // other params
}