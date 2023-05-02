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
    var isSyncInProgress = true;
    var functionalTestSyncProgressListener =
        FunctionalTestSyncProgressListener();
    syncService.addProgressListener(functionalTestSyncProgressListener);
    functionalTestSyncProgressListener.streamController.stream
        .listen((syncProgress) async {
      _logger.info(
          'Sync process completed. Sync Status: ${syncProgress.syncStatus}');
      if (syncProgress.syncStatus == SyncStatus.success ||
          syncProgress.syncStatus == SyncStatus.failure) {
        isSyncInProgress = false;
      }
      var keyInfoList = syncProgress.keyInfoList;
      if (keyInfoList != null) {
        for (KeyInfo key in keyInfoList) {
          _logger.info(key);
        }
      }
    });
    syncService.sync();

    int started = DateTime.now().millisecondsSinceEpoch;
    int waitUntilThis =
        started + 40000;
    while (isSyncInProgress &&
        DateTime.now().millisecondsSinceEpoch < waitUntilThis) {
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
