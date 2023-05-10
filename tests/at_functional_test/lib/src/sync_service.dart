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

  Future<void> syncData(SyncService syncService,
      {SyncOptions? syncOptions}) async {
    // Setting sync request threshold to 1 to expedite sync process
    SyncServiceImpl.syncRequestThreshold = 1;
    SyncServiceImpl.queueSize = 1;
    SyncServiceImpl.syncRequestTriggerInSeconds = 1;
    SyncServiceImpl.syncRunIntervalSeconds = 1;
    var isInSyncProgress = true;

    int startTimeInMS = DateTime.now().millisecondsSinceEpoch;
    //  start time plus 30 seconds (30000 milliseconds)
    int maxWaitTime = startTimeInMS + 30000;

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
      if (syncOptions == null) {
        if (((syncProgress.syncStatus == SyncStatus.success) &&
                (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
            (syncProgress.syncStatus == SyncStatus.failure)) {
          isInSyncProgress = false;
        }
      } else {
        _logger.info(
            'Found SyncOptions...Waiting until the ${syncOptions.key} is synced to client');
        // Since the KeyInfoList is empty, wait until the required key is synced.
        // Hence call sync method to expedite the sync progress
        if (syncProgress.keyInfoList == null ||
            syncProgress.keyInfoList!.isEmpty) {
          syncService.sync();
          return;
        }
        for (KeyInfo keyInfo in syncProgress.keyInfoList!) {
          _logger.info(keyInfo);
          if (syncOptions.key.isNotNull && (keyInfo.key == syncOptions.key)) {
            _logger.info(
                'Found ${syncOptions.key} in key list info | ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId}');
            isInSyncProgress = false;
          }
        }
      }
      _logger.info(
          'Completed sync| ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId}');
    });
    // When localCommitId and serverCommitId are not equal, calling sync method to expedite sync process

    while (isInSyncProgress &&
        DateTime.now().millisecondsSinceEpoch <
            maxWaitTime) //  time is less than 30 seconds
    {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}

/// Additional options for client to wait on sync
class SyncOptions {
  /// Waits until the key is sync'ed to the client
  String? key;
}

class FunctionalTestSyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController = StreamController();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}
