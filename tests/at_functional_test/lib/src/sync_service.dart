import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
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
    // Setting sync request threshold to 1 to expedite sync process
    SyncServiceImpl.syncRequestThreshold = 1;
    SyncServiceImpl.queueSize = 1;
    SyncServiceImpl.syncRequestTriggerInSeconds = 1;
    SyncServiceImpl.syncRunIntervalSeconds = 1;
    var isInSyncProgress = true;
    var functionalTestSyncProgressListener =
        FunctionalTestSyncProgressListener();
    // initialise sync and add listener
    syncService.addProgressListener(functionalTestSyncProgressListener);
    // Calling sync method to expedite sync process
    syncService.sync();
    functionalTestSyncProgressListener.streamController.stream
        .listen((syncProgress) async {
      // Exit the sync process when either of the conditions are met,
      // 1. If syncStatus is success && localCommitId is equal to serverCommitID (or) If syncStatus is failure
      // 2. When sync process exceeds the max timeout (30 seconds)
      if (((syncProgress.syncStatus == SyncStatus.success) &&
              (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
          (syncProgress.syncStatus == SyncStatus.failure)) {
        _logger.info('sync completed');
        isInSyncProgress = false;
      }
    });
    // When localCommitId and serverCommitId are not equal, calling sync method to expedite sync process
    syncService.sync();
    int startTimeInMS = DateTime.now().millisecondsSinceEpoch;
    //  start time plus 30 seconds (30000 milliseconds)
    int maxWaitTime = startTimeInMS + 30000;
    while (isInSyncProgress &&
        DateTime.now().millisecondsSinceEpoch <
            maxWaitTime) //  time is less than 30 seconds
    {
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
