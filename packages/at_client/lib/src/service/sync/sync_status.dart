import 'package:at_client/at_client.dart';

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
  AtClientException? atClientException;

  @override
  String toString() {
    return 'SyncProgress{atSign: $atSign, syncStatus: $syncStatus,'
        '\n\t isInitialSync: $isInitialSync, startedAt: $startedAt,'
        ' completedAt: $completedAt, message: $message, '
        '\n\t keyInfoList:$keyInfoList,'
        '\n\t localCommitIdBeforeSync:$localCommitIdBeforeSync, localCommitId:$localCommitId, serverCommitId:$serverCommitId}';
  }
}
