import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show CommitOp;
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

abstract class SyncService {
  /// Sync local secondary and cloud secondary.
  ///
  /// Enqueues a sync request and triggers a sync run as soon as the
  /// currently-in-flight run (if any) completes; if none is in flight,
  /// the run starts on the next event-loop tick. After [stop] is
  /// called this method becomes a no-op.
  ///
  /// This method will be obsolete in the forthcoming alternative implementation which takes an event-driven
  /// streaming approach to syncing. Instead of requesting a sync, you will request that processing
  /// of the data events (whether originating from client or server) be paused or resumed or re-initialized
  ///
  /// If local secondary is ahead, pushes the changes to the cloud secondary.
  /// If cloud secondary is ahead, pulls the changes to the local secondary.
  ///
  /// Register to onDone callback. The callback accepts instance of [SyncResult].
  ///
  /// Usage
  /// ```dart
  /// var syncService = AtClientManager.getInstance().syncService;
  ///
  /// syncService.sync(_onDoneCallback); //or
  /// syncService.sync();
  ///
  /// // Called when sync process is successful.
  /// void _onDoneCallback(syncResult){
  ///   print(syncResult.syncStatus);
  ///   print(syncResult.lastSyncedOn);
  /// }
  /// ```
  void sync(
      {@Deprecated('Use SyncProgressListener') Function? onDone,
      Function? onError});

  /// Call this method to set the Global onDone callback.
  /// This method will be called when a sync is completed.
  /// When a specific onDone function is passed to the sync Function, Then the specific onDone is called.
  @Deprecated('Use SyncProgressListener')
  void setOnDone(Function onDone);

  /// Returns true if local and cloud secondary are in sync. false otherwise
  Future<bool> isInSync();

  /// Returns true if sync is in-progress; else false.
  bool get isSyncInProgress;

  /// Adds a listener that is notified about [SyncProgress]
  void addProgressListener(SyncProgressListener listener);

  /// Removes a sync progress listener
  void removeProgressListener(SyncProgressListener listener);

  /// Remove all progress listeners
  void removeAllProgressListeners();

  /// Halts sync activity. Cancels the stats-notification subscription,
  /// drains any pending requests in the queue (their callbacks are
  /// invoked with an error), removes all progress listeners, and
  /// causes future [sync] calls to become no-ops until [restart] is
  /// invoked. Idempotent — calling [stop] when already stopped is a
  /// no-op.
  Future<void> stop();

  /// Reverses a prior [stop]: re-subscribes to stats notifications and
  /// allows new [sync] calls to fire again. Progress listeners removed
  /// by [stop] are NOT restored — the caller must re-add them via
  /// [addProgressListener]. The sync queue starts empty after restart
  /// (it was drained on [stop]). Idempotent — calling [restart] when
  /// not stopped is a no-op.
  Future<void> restart();
}

class KeyInfo {
  String key;
  SyncDirection syncDirection;
  ConflictInfo? conflictInfo;
  late CommitOp commitOp;

  KeyInfo(this.key, this.syncDirection, this.commitOp);

  @override
  String toString() {
    return 'KeyInfo{key: $key, syncDirection: $syncDirection , conflictInfo: $conflictInfo, commitOp: $commitOp}';
  }
}

enum SyncDirection { localToRemote, remoteToLocal }

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

class SyncResult {
  SyncStatus syncStatus = SyncStatus.notStarted;
  AtClientException? atClientException;
  DateTime? lastSyncedOn;
  bool dataChange = true;
  List<KeyInfo> keyInfoList = [];

  @override
  String toString() {
    return 'Sync status: $syncStatus lastSyncedOn: $lastSyncedOn Exception: $atClientException';
  }
}

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

///Enum to represent the sync status
enum SyncStatus { started, notStarted, success, failure }

class SyncProgress {
  SyncStatus? syncStatus;
  bool isInitialSync = false;
  DateTime? startedAt;
  DateTime? completedAt;
  String? message;
  String? atSign;
  List<KeyInfo>? keyInfoList;
  int? localCommitIdBeforeSync;
  int? localCommitId;
  int? serverCommitId;
  AtClientException? atClientException;

  @override
  String toString() {
    return 'SyncProgress{atSign: $atSign, syncStatus: $syncStatus,'
        '\n\t isInitialSync: $isInitialSync, startedAt: $startedAt,'
        ' completedAt: $completedAt, message: $message, '
        '\n\t keyInfoList:$keyInfoList,'
        '\n\t localCommitIdBeforeSync:$localCommitIdBeforeSync, localCommitId:$localCommitId, serverCommitId:$serverCommitId}';
  }
}

abstract class SyncProgressListener {
  /// Notifies the registered listener for the [SyncProgress]
  /// Caller has to register the listener using  atClientManager.syncService.addProgressListener(...)
  /// Caller can use [SyncProgress.atSign] to know for which atSign the event was triggered.
  void onSyncProgressEvent(SyncProgress syncProgress);
}

@experimental
class SyncTelemetryEvent extends AtTelemetryEvent {
  SyncTelemetryEvent(super.name, super.value);
}
