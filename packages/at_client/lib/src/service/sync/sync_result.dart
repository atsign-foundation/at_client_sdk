import 'package:at_client/src/service/sync/sync_status.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_commons.dart';

///Class to represent sync response.
class SyncResult {
  SyncStatus syncStatus = SyncStatus.notStarted;
  AtClientException? atClientException;
  DateTime? lastSyncedOn;
  bool dataChange = true;
  List<KeyInfo> keyInfoList = [];
  late int localCommitId;
  late int serverCommitId;

  @override
  String toString() {
    return 'Sync status: $syncStatus lastSyncedOn: $lastSyncedOn Exception: $atClientException';
  }
}
