///Enum to represent the sync status
enum SyncStatus { started, notStarted, success, failure }

class SyncProgress {
  SyncStatus? syncStatus;
  bool isInitialSync = false;
  DateTime? startedAt;
  DateTime? completedAt;
  String? message;
  // other params
}