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
    late TestSyncProgressListener testSyncProgressListener;
    try {
      _logger.info('syncData starting for $atSign ($logLabel)');

      SyncServiceImpl.queueSize = 1;

      testSyncProgressListener = TestSyncProgressListener(logLabel);
      syncSvc.addProgressListener(testSyncProgressListener);

      // NOTE: a budget in time, not in rounds. The service coalesces
      // requests and answers a system request from its cache, so a burst of
      // terminal events can arrive within a hundred milliseconds of each
      // other while the commit the fresh check saw is still only in a stats
      // notification on its way; five of those in a row proved nothing about
      // whether the next round would pull it.
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      int syncCount = 1;

      // Call to syncService.sync to expedite the sync progress
      syncImpl.sync();
      // ignore: invalid_use_of_visible_for_testing_member
      unawaited(syncImpl.processSyncRequests());

      await for (final SyncProgress syncProgress
          in testSyncProgressListener.streamController.stream) {
        for (final KeyInfo ki in syncProgress.keyInfoList ?? []) {
          _logger.finer('${ki.syncDirection} ${ki.key}');
        }
        if (syncProgress.syncStatus != SyncStatus.success &&
            syncProgress.syncStatus != SyncStatus.failure) {
          continue;
        }
        // NOTE: a terminal event says a run finished, not that THIS call's
        // work is done. It can belong to an earlier run, and a failure event
        // must mean try again, never "done" — returning on one strands this
        // call's own request mid-flight. Only the service's own fresh answer
        // settles it.
        if (await syncImpl.isInSync()) {
          _logger.info('SyncProgress $logLabel: ${syncProgress.syncStatus};'
              ' isInSync() confirms server and local are in sync');
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          _logger.shout('SyncProgress $logLabel: ${syncProgress.syncStatus}'
              ' local ${syncProgress.localCommitId}'
              ' remote ${syncProgress.serverCommitId}');
          throw StateError(
              'Have synced $syncCount times over 15s but still not in sync');
        }
        if (syncCount > 1) {
          _logger.shout('SyncProgress $logLabel: ${syncProgress.syncStatus}'
              ' but not in sync; syncing again');
        } else {
          _logger.info('SyncProgress $logLabel: ${syncProgress.syncStatus}'
              ' but not in sync; syncing again');
        }
        syncCount++;
        // Let the round the last trigger started finish, and a pending stats
        // notification land, before asking again.
        await Future.delayed(const Duration(milliseconds: 250));
        // Call to syncService.sync to expedite the sync progress
        syncImpl.sync();
        // ignore: invalid_use_of_visible_for_testing_member
        unawaited(syncImpl.processSyncRequests());
      }

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
