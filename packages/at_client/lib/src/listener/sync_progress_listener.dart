import 'package:at_client/src/service/sync/sync_status.dart';

abstract class SyncProgressListener {
  /// Notifies the registered listener for the [SyncProgress]
  /// Caller has to register the listener using  atClientManager.syncService.addProgressListener(...)
  /// Caller can use [SyncProgress.atSign] to know for which atSign the event was triggered.
  void onSyncProgressEvent(SyncProgress syncProgress);
}
