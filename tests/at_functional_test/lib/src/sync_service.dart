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
    Completer syncOutcome = Completer();
    late TestSyncProgressListener testSyncProgressListener;
    try {
      _logger.info('syncData starting for $atSign ($logLabel)');

      SyncServiceImpl.queueSize = 1;
      SyncServiceImpl.syncRequestThreshold = 1;
      SyncServiceImpl.syncRequestTriggerInSeconds = 1;
      SyncServiceImpl.syncRunIntervalSeconds = 1;

      testSyncProgressListener = TestSyncProgressListener(logLabel);
      syncSvc.addProgressListener(testSyncProgressListener);

      final int maxSyncCount = 5;
      int syncCount = 1;
      testSyncProgressListener.streamController.stream
          .listen((SyncProgress syncProgress) async {
        for (final KeyInfo ki in syncProgress.keyInfoList ?? []) {
          _logger.finer('${ki.syncDirection} ${ki.key}');
        }
        if (syncProgress.syncStatus == SyncStatus.success &&
            syncProgress.localCommitId != syncProgress.serverCommitId) {
          if (syncCount >= maxSyncCount) {
            isSyncInProgress = false;
            _logger.shout('SyncProgress $logLabel: ${syncProgress.syncStatus}'
                ' local ${syncProgress.localCommitId}'
                ' remote ${syncProgress.serverCommitId}');
            syncOutcome.completeError(
                'Have synced $syncCount times but still not in sync');
          }
          if (syncCount > 1) {
            _logger.shout('SyncProgress $logLabel: ${syncProgress.syncStatus}'
                ' local ${syncProgress.localCommitId}'
                ' remote ${syncProgress.serverCommitId}');
            _logger.shout('Syncing again');
          } else {
            _logger.info('SyncProgress $logLabel: ${syncProgress.syncStatus}'
                ' local ${syncProgress.localCommitId}'
                ' remote ${syncProgress.serverCommitId}');
            _logger.info('Syncing again');
          }
          syncCount++;
          // Call to syncService.sync to expedite the sync progress
          syncImpl.sync();
          // ignore: invalid_use_of_visible_for_testing_member
          unawaited(syncImpl.processSyncRequests(
            respectSyncRequestQueueSizeAndRequestTriggerDuration: false,
          ));
        } else if (syncProgress.syncStatus == SyncStatus.success ||
            syncProgress.syncStatus == SyncStatus.failure) {
          isSyncInProgress = false;
          syncOutcome.complete();
        }
      });

      // Call to syncService.sync to expedite the sync progress
      syncImpl.sync();
      // ignore: invalid_use_of_visible_for_testing_member
      unawaited(syncImpl.processSyncRequests(
        respectSyncRequestQueueSizeAndRequestTriggerDuration: false,
      ));

      await syncOutcome.future;

      _logger.info('syncData complete for $atSign $logLabel');
    } finally {
      syncSvc.removeProgressListener(testSyncProgressListener);
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
