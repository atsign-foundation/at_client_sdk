import 'dart:async';

import 'package:at_client/at_client.dart';
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

    E2ETestSyncProgressListener e2eTestSyncProgressListener =
        E2ETestSyncProgressListener();
    syncService.addProgressListener(e2eTestSyncProgressListener);

    e2eTestSyncProgressListener.streamController.stream
        .listen((SyncProgress syncProgress) async {
      lastReceivedDateTime = DateTime.now().toUtc();
      // Exit the sync process when either of the conditions are met,
      // 1. If SyncOptions.key is set, wait until the key is synced.
      // 2. else, wait until sync is completed
      if (syncOptions != null && syncOptions.key.isNotNull) {
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
          if (syncOptions.key.isNotNull && (keyInfo.key == syncOptions.key)) {
            _logger.info(
                'Found ${syncOptions.key} in key list info | ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId}');
            isSyncInProgress = false;
          }
        }
      } else {
        if (((syncProgress.syncStatus == SyncStatus.success) &&
                (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
            (syncProgress.syncStatus == SyncStatus.failure)) {
          isSyncInProgress = false;
        }
      }
      _logger.info(
          'Completed sync for ${syncProgress.atSign}| ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId} | Processing time: ${syncProgress.completedAt!.difference(syncProgress.startedAt!).inMilliseconds} millis');
    });

    /// If SyncOptions.waitForFullSyncToComplete is true, wait until full sync is completed (OR)
    /// else, wait until
    ///   a. When totalWaitTime is less than 2 minutes
    ///   b. When transientWaitTime is less than 30 seconds
    ///   c. When isSyncInProgress is set to true
    while ((syncOptions != null &&
            syncOptions.waitForFullSyncToComplete == true &&
            isSyncInProgress == true) ||
        (DateTime.now().toUtc().difference(startTime).inMilliseconds <
                totalWaitTimeInMills) &&
            (DateTime.now()
                    .toUtc()
                    .difference(lastReceivedDateTime)
                    .inMilliseconds <
                transientWaitTimeInMills) &&
            (isSyncInProgress == true)) {
      syncService.sync();
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}

/// Additional options for client to wait on sync
class SyncOptions {
  /// Waits until the key is sync'ed to the client
  String? key;

  /// When set to true, wait until the client and server are in sync, irrespective of the sync time-out conditions
  bool waitForFullSyncToComplete = false;
}

class E2ETestSyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController = StreamController();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}
