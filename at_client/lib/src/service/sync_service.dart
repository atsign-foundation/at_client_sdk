/// SyncService is an abstract class that can implmented to keep local and cloud secondary data in sync.
abstract class SyncService {
  /// Sync local secondary and cloud secondary.
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
  void sync({Function? onDone});

  /// Returns true if local and cloud secondary are in sync. false otherwise
  Future<bool> isInSync();
}
