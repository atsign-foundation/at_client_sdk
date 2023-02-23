import 'package:at_client/src/listener/sync_progress_listener.dart';
import 'package:at_client/src/service/sync/sync_status.dart';
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart';

abstract class SyncService {
  /// Sync local secondary and cloud secondary.
  ///
  /// NB: With current SyncServiceImpl this may not immediately sync. Instead, it will enqueue a request for sync to take place.
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
  void sync({@Deprecated('Use SyncProgressListener') Function? onDone, Function? onError});

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

@experimental
class SyncTelemetryEvent extends AtTelemetryEvent {
  SyncTelemetryEvent(String name, value) : super(name, value);
}
