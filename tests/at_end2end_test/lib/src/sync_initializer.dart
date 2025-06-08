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

  bool isSyncInProgress = false;
  Future<void> syncData(SyncService syncSvc) async {
    if (isSyncInProgress) {
      throw StateError('Sync already in progress');
    }

    isSyncInProgress = true;
    try {
      final atSign = AtClientManager.getInstance().atClient.getCurrentAtSign();
      _logger.info('syncData starting for $atSign');

      SyncServiceImpl.queueSize = 1;
      SyncServiceImpl.syncRequestThreshold = 1;
      SyncServiceImpl.syncRequestTriggerInSeconds = 1;
      SyncServiceImpl.syncRunIntervalSeconds = 1;

      DateTime startTime = DateTime.now().toUtc();
      DateTime lastReceivedDateTime = DateTime.now().toUtc();
      Duration maxTotalWaitTime = Duration(minutes: 2);
      int maxTotalWaitTimeMillis = maxTotalWaitTime.inMilliseconds;
      Duration maxTransientWaitTime = Duration(seconds: 15);
      int maxTransientWaitTimeMillis = maxTransientWaitTime.inMilliseconds;

      E2ETestSyncProgressListener e2eTestSyncProgressListener =
          E2ETestSyncProgressListener();
      syncSvc.addProgressListener(e2eTestSyncProgressListener);

      e2eTestSyncProgressListener.streamController.stream
          .listen((SyncProgress syncProgress) async {
        for (final KeyInfo ki in syncProgress.keyInfoList ?? []) {
          _logger.finer('${ki.syncDirection} ${ki.key}');
        }
        lastReceivedDateTime = DateTime.now().toUtc();
        if (((syncProgress.syncStatus == SyncStatus.success) &&
                (syncProgress.localCommitId == syncProgress.serverCommitId)) ||
            (syncProgress.syncStatus == SyncStatus.failure)) {
          isSyncInProgress = false;
        }
      });

      SyncServiceImpl syncImpl = syncSvc as SyncServiceImpl;
      // Call to syncService.sync to expedite the sync progress
      syncImpl.sync();
      // ignore: invalid_use_of_visible_for_testing_member
      await syncImpl.processSyncRequests(
        respectSyncRequestQueueSizeAndRequestTriggerDuration: false,
      );

      while (isSyncInProgress) {
        final now = DateTime.now().toUtc();
        if (now.difference(lastReceivedDateTime).inMilliseconds >
            maxTransientWaitTimeMillis) {
          throw StateError(
              'Sync duration exceeded maxTransientWaitTime ($maxTransientWaitTime)');
        }
        if (now.difference(startTime).inMilliseconds > maxTotalWaitTimeMillis) {
          throw StateError(
              'Sync duration exceeded maxTotalWaitTime ($maxTotalWaitTime)');
        }
        await Future.delayed(Duration(milliseconds: 10));
      }
      syncSvc.removeProgressListener(e2eTestSyncProgressListener);
      _logger.info('syncData complete for $atSign');
    } finally {
      isSyncInProgress = false;
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
