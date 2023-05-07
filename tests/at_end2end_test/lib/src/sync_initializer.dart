import 'dart:async';

import 'package:at_client/at_client.dart';

// ignore: implementation_imports
import 'package:at_client/src/service/sync_service.dart';

// ignore: implementation_imports
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
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
      {SyncParameters? syncParameters}) async {
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
      print('SyncService| $syncProgress');
      // Exit the sync process when either of the conditions are met,
      // 1. If syncStatus is success && localCommitId is equal to serverCommitID (or)
      //    If syncStatus is failure
      // 2. When sync process exceeds the max timeout that is 30 seconds
      if (syncParameters == null) {
        if (((syncProgress.syncStatus == SyncStatus.success) &&
                (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
            (syncProgress.syncStatus == SyncStatus.failure)) {
          isSyncInProgress = false;
        }
      } else if (syncProgress.keyInfoList != null) {
        for (KeyInfo keyInfo in syncProgress.keyInfoList!) {
          _logger.info(keyInfo);
          if (syncParameters.key.isNotNull &&
              (keyInfo.key == syncParameters.key)) {
            print(
                'Found ${syncParameters.key} in key list info | ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId}');
            isSyncInProgress = false;
          }
        }
      }
      print(
          'Completed sync| ${syncProgress.syncStatus} | localCommitId: ${syncProgress.localCommitId} | ServerCommitId: ${syncProgress.serverCommitId}');
    });

    while (isSyncInProgress &&
        DateTime.now().millisecondsSinceEpoch < waitUntilThis) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}

class SyncParameters {
  String? key;
  CommitOp? commitOp;
}

class E2ETestSyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController = StreamController();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}
