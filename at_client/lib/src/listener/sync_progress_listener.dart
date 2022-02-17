import 'package:at_client/src/service/sync/sync_status.dart';

abstract class SyncProgressListener {
  /// Notifies the registered listener for the [SyncProgress]
  /// Client has to register the listener using  atClientManager.syncService.addProgressListener(...)
  void onSyncEvent(SyncProgress syncProgress);
}
