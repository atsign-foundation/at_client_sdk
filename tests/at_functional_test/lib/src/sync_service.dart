import 'dart:async';

import 'package:at_client/at_client.dart';

// ignore: implementation_imports
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('FunctionalTestSyncService');

/// The class represents the sync services for the end to end tests
class FunctionalTestSyncService {
  static final FunctionalTestSyncService _singleton =
      FunctionalTestSyncService._internal();

  FunctionalTestSyncService._internal();

  factory FunctionalTestSyncService.getInstance() {
    return _singleton;
  }

  bool isSyncInProgress = false;

  Future<void> syncData({SyncService? syncSvc, String? label}) async {
    if (isSyncInProgress) {
      throw StateError('Sync already in progress');
    }

    String logLabel = label == null ? '' : '($label)';
    await Future.delayed(Duration(milliseconds: 100));

    final atSign = AtClientManager.getInstance().atClient.getCurrentAtSign();
    syncSvc ??= AtClientManager.getInstance().atClient.syncService;
    SyncServiceImpl syncImpl = syncSvc as SyncServiceImpl;

    isSyncInProgress = true;
    try {
      _logger.info('syncData starting for $atSign ($logLabel)');

      SyncServiceImpl.queueSize = 1;
      SyncServiceImpl.syncRequestThreshold = 1;
      SyncServiceImpl.syncRequestTriggerInSeconds = 1;
      SyncServiceImpl.syncRunIntervalSeconds = 1;

      DateTime startTime = DateTime.now().toUtc();
      DateTime lastReceivedDateTime = DateTime.now().toUtc();
      Duration maxTotalWaitTime = Duration(minutes: 2);
      int maxTotalWaitTimeMillis = maxTotalWaitTime.inMilliseconds;
      Duration maxTransientWaitTime = Duration(seconds: 30);
      int maxTransientWaitTimeMillis = maxTransientWaitTime.inMilliseconds;

      TestSyncProgressListener testSyncProgressListener =
          TestSyncProgressListener(logLabel);
      syncSvc.addProgressListener(testSyncProgressListener);

      testSyncProgressListener.streamController.stream
          .listen((SyncProgress syncProgress) async {
        for (final KeyInfo ki in syncProgress.keyInfoList ?? []) {
          _logger.finer('${ki.syncDirection} ${ki.key}');
        }
        lastReceivedDateTime = DateTime.now().toUtc();
        if (syncProgress.syncStatus == SyncStatus.success &&
            syncProgress.localCommitId != syncProgress.serverCommitId) {
          _logger.warning('SyncProgress $logLabel: ${syncProgress.syncStatus}'
              ' local ${syncProgress.localCommitId}'
              ' remote ${syncProgress.serverCommitId}');
          _logger.warning('Calling sync() again');
          syncImpl.sync();
        } else if (syncProgress.syncStatus == SyncStatus.success ||
            syncProgress.syncStatus == SyncStatus.failure) {
          isSyncInProgress = false;
        }
      });

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
      syncSvc.removeProgressListener(testSyncProgressListener);
      _logger.info('syncData complete for $atSign $logLabel');
    } finally {
      isSyncInProgress = false;
    }
  }
}

class TestSyncProgressListener extends SyncProgressListener {
  String logLabel;

  TestSyncProgressListener(this.logLabel);

  StreamController<SyncProgress> streamController = StreamController();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    _logger.info('Received SyncProgress $logLabel: ${syncProgress.syncStatus}');
    streamController.add(syncProgress);
  }
}
