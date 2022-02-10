import 'package:at_client/src/service/sync/sync_status.dart';

abstract class SyncProgressListener {
  void onSync(SyncProgress syncProgress);
}
