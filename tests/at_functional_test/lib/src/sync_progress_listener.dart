import 'dart:async';

import 'package:at_client/at_client.dart';

class MySyncProgressListener extends SyncProgressListener {
  final bool skipSyncStartedEvent;

  MySyncProgressListener(this.skipSyncStartedEvent);

  StreamController<SyncProgress> streamController =
      StreamController<SyncProgress>();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    if (skipSyncStartedEvent && syncProgress.syncStatus == SyncStatus.started) {
      return;
    } else {
      streamController.add(syncProgress);
    }
  }
}
