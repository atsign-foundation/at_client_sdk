import 'package:at_client/at_client.dart';

enum ResolutionStrategy { useLocal, useRemote }

enum SyncType {
  initialPushToRemote,
  initialPullFromRemote,
  pullFromRemote,
  pushToRemote
}

class SyncEntry {
  String commitID;
  String decryptedValue;
  SyncEntry(this.commitID, this.decryptedValue);
}

class ResolutionContext {
  AtKey? key;
  SyncEntry? localEntry;
  SyncEntry? remoteEntry;
  SyncType? syncType;
}

class ConflictInfo {
  dynamic remoteValue;
  dynamic localValue;
  String? errorOrExceptionMessage;

  @override
  String toString() {
    return 'ConflictInfo{remoteValue: $remoteValue, localValue: $localValue, errorOrExceptionMessage: $errorOrExceptionMessage}';
  }
}
