import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/service/sync_service_impl.dart';

/// [Deprecated] Use [AtClientManager.syncService]
class SyncManagerImpl {
  static final SyncManagerImpl _singleton = SyncManagerImpl._internal();

  SyncManagerImpl._internal();

  factory SyncManagerImpl.getInstance() {
    return _singleton;
  }

  final Map<String?, SyncManager> _syncManagerMap = {};

  SyncManager? getSyncManager(String? atSign) {
    if (!_syncManagerMap.containsKey(atSign)) {
      var syncManager = SyncManager(atSign);
      _syncManagerMap[atSign] = syncManager;
    }
    return _syncManagerMap[atSign];
  }
}
