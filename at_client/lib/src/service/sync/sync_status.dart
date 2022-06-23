import 'package:at_client/src/service/sync_service_impl.dart';

///Enum to represent the sync status
enum SyncStatus { started, notStarted, success, failure }

class SyncProgress {
  SyncStatus? syncStatus;
  bool isInitialSync = false;
  DateTime? startedAt;
  DateTime? completedAt;
  String? message;
  String? atSign;
  List<KeyInfo>? keyInfoList;
  int? localCommitIdBeforeSync;
  int? localCommitId;
  int? serverCommitId;

  @override
  String toString() {
    return 'SyncProgress{atSign: $atSign, syncStatus: $syncStatus, isInitialSync: $isInitialSync, startedAt: $startedAt, completedAt: $completedAt, message: $message, '
        'keyInfoList:$keyInfoList, localCommitIdBeforeSync:$localCommitIdBeforeSync, localCommitId:$localCommitId, serverCommitId:$serverCommitId}';
  }
}
