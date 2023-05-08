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

  Future<void> syncData(SyncService syncService,
      {SyncOptions? syncOptions}) async {
    SyncServiceImpl.queueSize = 1;
    SyncServiceImpl.syncRequestThreshold = 1;
    SyncServiceImpl.syncRequestTriggerInSeconds = 1;
    SyncServiceImpl.syncRunIntervalSeconds = 1;
    var isSyncInProgress = true;

    // Call to syncService.sync to expedite the sync progress
    syncService.sync();

    E2ETestSyncProgressListener e2eTestSyncProgressListener =
        E2ETestSyncProgressListener();
    syncService.addProgressListener(e2eTestSyncProgressListener);

    int started = DateTime.now().millisecondsSinceEpoch;
    int waitUntilThis =
        started + 30000; // 30 seconds is more than enough time to wait

    e2eTestSyncProgressListener.streamController.stream
        .listen((SyncProgress syncProgress) async {
      _logger.info('SyncService| $syncProgress');
      // Exit the sync process when either of the conditions are met,
      // 1. If syncStatus is success && localCommitId is equal to serverCommitID (or)
      //    If syncStatus is failure
      // 2. When sync process exceeds the max timeout that is 30 seconds
      if (syncOptions == null) {
        if (((syncProgress.syncStatus == SyncStatus.success) &&
                (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
            (syncProgress.syncStatus == SyncStatus.failure)) {
          isSyncInProgress = false;
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
            isSyncInProgress = false;
          }
        }
      }
      _logger.info(
          'Completed sync| ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId}');
    });

    while (isSyncInProgress &&
        DateTime.now().millisecondsSinceEpoch < waitUntilThis) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}

/// Additional options for client to wait on sync
class SyncOptions {
  /// Waits until the key is sync'ed to the client
  String? key;
}

class E2ETestSyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController = StreamController();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}
