import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_utils/at_logger.dart';

/// The class represents the sync services for the end to end tests
class E2ESyncService {
  static final _logger = AtSignLogger('E2ESyncService');

  static final E2ESyncService _singleton = E2ESyncService._internal();

  E2ESyncService._internal();

  factory E2ESyncService.getInstance() {
    return _singleton;
  }

  Future<void> syncData(SyncService syncService) async {
    SyncServiceImpl.syncRequestThreshold = 1;
    SyncServiceImpl.syncRequestTriggerInSeconds = 1;
    SyncServiceImpl.syncRunIntervalSeconds = 1;

    var _isSyncInProgress = true;
    var e2eTestSyncProgressListener = E2ETestSyncProgressListener();
    syncService.addProgressListener(e2eTestSyncProgressListener);
    syncService.sync();
    e2eTestSyncProgressListener.streamController.stream
        .listen((syncProgress) async {
      if (syncProgress.syncStatus == SyncStatus.success ||
          syncProgress.syncStatus == SyncStatus.failure) {
        _isSyncInProgress = false;
        print (syncProgress);
      }
    });
    while (_isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}

class E2ETestSyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController = StreamController();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}
