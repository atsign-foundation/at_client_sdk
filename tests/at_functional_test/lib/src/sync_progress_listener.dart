import 'dart:async';

import 'package:at_client/at_client.dart';

class MySyncProgressListener extends SyncProgressListener {
  final bool skipSyncStartedEvent;

  MySyncProgressListener(this.skipSyncStartedEvent);

  StreamController<SyncProgress> streamController =
      StreamController<SyncProgress>();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    // When the caller opted to skip the per-iteration "started" event
    // they want terminal-only signals; per-batch [SyncStatus.inProgress]
    // events fall in the same "non-terminal noise" bucket and are
    // dropped together. Tests that actually want to observe progress
    // can construct with `false`.
    if (skipSyncStartedEvent &&
        (syncProgress.syncStatus == SyncStatus.started ||
            syncProgress.syncStatus == SyncStatus.inProgress)) {
      return;
    } else {
      streamController.add(syncProgress);
    }
  }
}
