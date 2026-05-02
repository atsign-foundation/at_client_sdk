import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show CommitOp;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
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

///Enum to represent the sync status.
///
/// [inProgress] is emitted at intra-iteration checkpoints (currently:
/// after each batch processed by `_syncFromServer` / `_syncToRemote`)
/// so listeners can observe progress on long syncs without waiting
/// for the iteration to finish. Listeners that only care about
/// terminal events should filter to [success] / [failure].
enum SyncStatus { started, notStarted, inProgress, success, failure }

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

/// Adds [waitUntilCaughtUp] to every [SyncService] without forcing
/// existing implementers to add a method to satisfy a new abstract
/// member. Implemented as an extension (not a method on [SyncService]
/// or a mixin) so:
///
///   - third-party code that uses `implements SyncService` keeps
///     compiling unchanged;
///   - callers holding a [SyncService] typed reference can call
///     `syncSvc.waitUntilCaughtUp(...)` directly, no cast or opt-in
///     required;
///   - the body uses only the existing public API ([sync],
///     [addProgressListener], [removeProgressListener]), so the
///     behaviour rides on whatever progress events the underlying
///     [SyncService] emits — not on private internals of
///     `SyncServiceImpl`.
extension SyncServiceWaitUntilCaughtUp on SyncService {
  static final AtSignLogger _waitLogger =
      AtSignLogger(' SyncServiceWaitUntilCaughtUp ');

  /// Returns a [Future] that completes once the local commit id has
  /// caught up to the remote commit id **as it stood at the time of
  /// this call**. Captures the remote commit id reported by the first
  /// [SyncProgress] event that fires after the call and completes the
  /// future once a subsequent event reports
  /// `localCommitId >= snapshotServerCommitId`. New remote changes
  /// that arrive after the call do NOT extend the wait.
  ///
  /// If local is already caught up at the time of the next sync
  /// iteration (the iteration short-circuits with "server and local
  /// are in sync", emitting a [SyncStatus.success] event with both
  /// commit ids null), the future completes immediately.
  ///
  /// On a [SyncService] that emits per-batch [SyncStatus.inProgress]
  /// events (see [SyncServiceImpl] from `at_client` 3.x onward),
  /// completion can fire mid-iteration as soon as `localCommitId`
  /// crosses the captured snapshot — no need to wait for the entire
  /// pull/push run to finish.
  ///
  /// [onProgress], when supplied, is invoked for every [SyncProgress]
  /// event observed while waiting (including the [SyncStatus.inProgress]
  /// per-batch events on the pull and push paths). Use it to drive
  /// "syncing N of M" UIs — typically by reading
  /// `progress.localCommitId` against `progress.serverCommitId`. The
  /// callback fires before the catch-up completion check, so apps see
  /// the same final event the future completes on. Exceptions thrown
  /// by [onProgress] are caught and logged; they do not affect the
  /// completion logic.
  ///
  /// Transient sync failures while waiting are tolerated — the
  /// returned future does not reject on a [SyncStatus.failure] event;
  /// callers bound the wait by passing [timeout]. With no [timeout]
  /// and a stalled sync (e.g. network loss for the duration), the
  /// future hangs.
  ///
  /// Throws [TimeoutException] when [timeout] elapses before catch-up.
  Future<void> waitUntilCaughtUp({
    Duration? timeout,
    void Function(SyncProgress progress)? onProgress,
  }) {
    final completer = Completer<void>();
    int? snapshotServerCommitId;
    late final SyncProgressListener listener;

    void detach() {
      // Defer removal so we don't mutate the listener list while the
      // implementation is iterating it on the same call frame.
      Future.microtask(() => removeProgressListener(listener));
    }

    listener = _ClosureProgressListener((progress) {
      // Surface every event to the caller's progress callback first,
      // before the catch-up completion check, so apps see the same
      // final event we use to fulfil the future. Defensive try/catch:
      // a misbehaving callback must not derail the completion logic.
      if (onProgress != null) {
        try {
          onProgress(progress);
        } catch (e, st) {
          _waitLogger
              .warning('onProgress callback threw and was swallowed: $e\n$st');
        }
      }
      if (completer.isCompleted) return;
      if (snapshotServerCommitId == null) {
        // The "server and local are in sync" early-exit fires a
        // SyncStatus.success event with both commit ids null — treat
        // that as "already caught up at call time" and complete.
        if (progress.syncStatus == SyncStatus.success &&
            progress.serverCommitId == null &&
            progress.localCommitId == null) {
          detach();
          completer.complete();
          return;
        }
        // Wait for an event that actually carries commit ids.
        if (progress.serverCommitId == null) return;
        snapshotServerCommitId = progress.serverCommitId;
      }
      _waitLogger.shout('serverCommitId (target): $snapshotServerCommitId'
          ' localCommitId (actual): ${progress.localCommitId}');
      final local = progress.localCommitId;
      if (local != null && local >= snapshotServerCommitId!) {
        detach();
        completer.complete();
      }
    });

    addProgressListener(listener);
    // Trigger an iteration so a progress event is guaranteed to fire
    // even when nothing else is currently driving sync.
    sync();

    if (timeout == null) return completer.future;
    return completer.future.timeout(timeout, onTimeout: () {
      detach();
      throw TimeoutException(
        'waitUntilCaughtUp timed out after $timeout',
        timeout,
      );
    });
  }
}

/// Internal [SyncProgressListener] that delegates to a closure. Used by
/// [SyncServiceWaitUntilCaughtUp.waitUntilCaughtUp] so the extension can
/// register a one-shot listener without forcing each call site to
/// declare its own subclass.
class _ClosureProgressListener implements SyncProgressListener {
  final void Function(SyncProgress) _onEvent;

  _ClosureProgressListener(this._onEvent);

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) =>
      _onEvent(syncProgress);
}
