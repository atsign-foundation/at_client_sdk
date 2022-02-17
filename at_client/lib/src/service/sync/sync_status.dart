///Enum to represent the sync status
enum SyncStatus { started, notStarted, success, failure }

class SyncProgress {
  SyncStatus? syncStatus;
  bool isInitialSync = false;
  DateTime? startedAt;
  DateTime? completedAt;
  String? message;
  String? atSign;

  @override
  String toString() {
    return 'SyncProgress{atSign: $atSign, syncStatus: $syncStatus, isInitialSync: $isInitialSync, startedAt: $startedAt, completedAt: $completedAt, message: $message}';
  }
// other params

}
