import 'dart:async';

import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/service/sync_service.dart';
// ignore: implementation_imports
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_utils/at_logger.dart';

/// The class represents the sync services for the end to end tests
class E2ESyncService {
  // ignore: unused_field
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

    var isSyncInProgress = true;
    var e2eTestSyncProgressListener = E2ETestSyncProgressListener();
    syncService.addProgressListener(e2eTestSyncProgressListener);
    e2eTestSyncProgressListener.streamController.stream
        .listen((SyncProgress syncProgress) async {
      if (syncProgress.syncStatus == SyncStatus.success ||
          syncProgress.syncStatus == SyncStatus.failure) {
        isSyncInProgress = false;
      }
      var keyInfoList = syncProgress.keyInfoList;
      if (keyInfoList != null) {
        for (KeyInfo ki in keyInfoList) {
          _logger.info(ki);
        }
      }
    });
    syncService.sync();

    int started = DateTime.now().millisecondsSinceEpoch;
    int waitUntilThis = started + 30000; // 30 seconds is more than enough time to wait
    while (isSyncInProgress && DateTime.now().millisecondsSinceEpoch < waitUntilThis) {
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
