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

abstract class KeyConflictResolver {
  Future<ResolutionStrategy> resolve(ResolutionContext context);
}
