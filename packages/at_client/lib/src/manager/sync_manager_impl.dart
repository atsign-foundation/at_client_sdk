import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/sync_manager.dart';

/// [Deprecated] Use [AtClient.syncService]
@Deprecated("Use SyncService")
class SyncManagerImpl {
  static final SyncManagerImpl _singleton = SyncManagerImpl._internal();

  SyncManagerImpl._internal();

  factory SyncManagerImpl.getInstance() {
    return _singleton;
  }

  final Map<String?, SyncManager> _syncManagerMap = {};

  @Deprecated("Use SyncService")
  SyncManager? getSyncManager(String? atSign) {
    if (!_syncManagerMap.containsKey(atSign)) {
      var syncManager = SyncManager(atSign);
      _syncManagerMap[atSign] = syncManager;
    }
    return _syncManagerMap[atSign];
  }
}
