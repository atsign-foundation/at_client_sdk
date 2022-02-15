///Enum to represent the sync status
enum SyncStatus { started, notStarted, success, failure }

class SyncProgress {
  SyncStatus? syncStatus;
  bool isInitialSync = false;
  DateTime? startedAt;
  DateTime? completedAt;
  String? message;

  @override
  String toString() {
    return 'SyncProgress{syncStatus: $syncStatus, isInitialSync: $isInitialSync, startedAt: $startedAt, completedAt: $completedAt, message: $message}';
  }
// other params

}