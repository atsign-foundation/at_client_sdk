import 'dart:async';

import 'package:at_client/at_client.dart';
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
    SyncServiceImpl.queueSize = 1;
    SyncServiceImpl.syncRequestThreshold = 1;
    SyncServiceImpl.syncRequestTriggerInSeconds = 1;
    SyncServiceImpl.syncRunIntervalSeconds = 1;
    var isSyncInProgress = true;
    DateTime startTime = DateTime.now().toUtc();
    DateTime lastReceivedDateTime = DateTime.now().toUtc();
    int totalWaitTimeInMills = Duration(minutes: 2).inMilliseconds;
    int transientWaitTimeInMills = Duration(seconds: 30).inMilliseconds;

    // Call to syncService.sync to expedite the sync progress
    syncService.sync();

    FunctionalTestSyncProgressListener functionalTestSyncProgressListener =
        FunctionalTestSyncProgressListener();
    syncService.addProgressListener(functionalTestSyncProgressListener);

    functionalTestSyncProgressListener.streamController.stream
        .listen((SyncProgress syncProgress) async {
      lastReceivedDateTime = DateTime.now().toUtc();
      // Exit the sync process when either of the conditions are met,
      // 1. If syncStatus is success && localCommitId is equal to serverCommitID (or)
      //    If syncStatus is failure
      if (syncOptions == null) {
        if (((syncProgress.syncStatus == SyncStatus.success) &&
                (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
            (syncProgress.syncStatus == SyncStatus.failure)) {
          isSyncInProgress = false;
        }
      } else {
        _logger.info(
            'Found SyncOptions...Waiting until the ${syncOptions.key} is synced');
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
            isSyncInProgress = false;
          }
        }
      }
      _logger.info(
          'Completed sync| ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId}');
    });

    /// Wait when the following conditions are true
    ///  1. When totalWaitTime is less than 2 minutes AND
    ///  2. When transientWaitTime is less than 30 seconds AND
    ///  3. When isSyncInProgress is set to true
    ///  If any of the above condition fails, exit the sync loop.
    while (DateTime.now().toUtc().difference(startTime).inMilliseconds <
            totalWaitTimeInMills &&
        DateTime.now().toUtc().difference(lastReceivedDateTime).inMilliseconds <
            transientWaitTimeInMills &&
        isSyncInProgress) {
      syncService.sync();
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
