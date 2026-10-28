import 'package:at_client/at_client.dart';

class MySyncProgressListener extends SyncProgressListener {
  bool syncComplete = false;
  String syncResult = 'syncing';

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    if (syncProgress.syncStatus == SyncStatus.failure ||
        syncProgress.syncStatus == SyncStatus.success) {
      syncComplete = true;
    }
    if (syncProgress.syncStatus == SyncStatus.failure) {
      syncResult = 'Failed';
    }
    if (syncProgress.syncStatus == SyncStatus.success) {
      syncResult = 'Succeeded';
    }

    return;
  }
}
