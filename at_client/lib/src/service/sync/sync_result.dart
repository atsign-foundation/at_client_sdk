import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync/sync_status.dart';

///Class to represent sync response.
class SyncResult {
  SyncStatus syncStatus = SyncStatus.notStarted;
  AtClientException? atClientException;
  DateTime? lastSyncedOn;
  bool dataChange = true;

  @override
  String toString() {
    return 'Sync status: $syncStatus lastSyncedOn: $lastSyncedOn Exception: $atClientException';
  }
}
