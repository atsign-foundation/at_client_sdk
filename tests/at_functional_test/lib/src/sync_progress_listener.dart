import 'dart:async';

import 'package:at_client/at_client.dart';

class MySyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController =
      StreamController<SyncProgress>();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}
