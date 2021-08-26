import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service.dart';

class SyncManagerImpl {
  static final SyncManagerImpl _singleton = SyncManagerImpl._internal();

  SyncManagerImpl._internal();

  factory SyncManagerImpl.getInstance() {
    return _singleton;
  }

  final Map<String, SyncService> _syncManagerMap = {};

  /// Returns an instance of [SyncService] of the current atsign.
  SyncService getSyncManager(AtClient atClient) {
    if (!_syncManagerMap.containsKey(atClient.getCurrentAtSign())) {
      var syncService = SyncService(atClient);
      _syncManagerMap[atClient.getCurrentAtSign()!] = syncService;
    }
    return _syncManagerMap[atClient.getCurrentAtSign()]!;
  }
}
