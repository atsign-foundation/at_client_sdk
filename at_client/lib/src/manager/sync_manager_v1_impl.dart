import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/sync_manager_v1.dart';

class SyncManagerV1Impl {
  static final SyncManagerV1Impl _singleton = SyncManagerV1Impl._internal();

  SyncManagerV1Impl._internal();

  factory SyncManagerV1Impl.getInstance() {
    return _singleton;
  }

  final Map<String, SyncManagerV1> _syncManagerV1Map = {};

  SyncManagerV1 getSyncManager(String atSign, AtClientPreference preference) {
    if (!_syncManagerV1Map.containsKey(atSign)) {
      var syncManagerV1 = SyncManagerV1(atSign, preference);
      _syncManagerV1Map[atSign] = syncManagerV1;
    }
    return _syncManagerV1Map[atSign];
  }
}
