
import 'package:at_client/src/service/sync/sync_result.dart';
import 'package:uuid/uuid.dart';

enum SyncRequestSource { app, system }

class SyncRequest {
  late String id;
  SyncRequestSource requestSource = SyncRequestSource.app;
  late DateTime requestedOn;
  Function? onDone;
  Function? onError;
  SyncResult? result;

  SyncRequest({this.onDone, this.onError}) {
    id = Uuid().v4();
    requestedOn = DateTime.now().toUtc();
  }
}