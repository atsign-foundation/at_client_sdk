import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_utils/at_logger.dart';

/// The class represents the sync services for the functional tests
class FunctionalTestSyncService {
  final _logger = AtSignLogger('FunctionalTestSyncService');

  static final FunctionalTestSyncService _singleton =
      FunctionalTestSyncService._internal();

  FunctionalTestSyncService._internal();

  factory FunctionalTestSyncService.getInstance() {
    return _singleton;
  }

  Future<void> syncData(SyncService syncService) async {
    var isInSyncProgress = true;
    var functionalTestSyncProgressListener =
        FunctionalTestSyncProgressListener();
    // initialise sync and add listener
    syncService.addProgressListener(functionalTestSyncProgressListener);
    syncService.sync();
    functionalTestSyncProgressListener.streamController.stream
        .listen((syncProgress) async {
      // if syncStatus is success && localCommitId is equal to serverCommitID
      // or if syncStatus is failure, then sync is false.
      if (((syncProgress.syncStatus == SyncStatus.success) &&
              (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
          (syncProgress.syncStatus == SyncStatus.failure)) {
        _logger.info('sync completed');
        isInSyncProgress = false;
      }
    });
    int startTimeInMS = DateTime.now().millisecondsSinceEpoch;
    int maxWaitTime = startTimeInMS + 30000;
    while (isInSyncProgress &&
        DateTime.now().millisecondsSinceEpoch < maxWaitTime) {
      _logger.info('sync in progress');
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}

class FunctionalTestSyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController = StreamController();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}
