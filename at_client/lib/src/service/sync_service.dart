import 'package:at_client/src/service/sync_service_impl.dart';

abstract class SyncService {
  /// Sync local secondary and cloud secondary.
  ///
  /// If local secondary is ahead, pushes the changes to the cloud secondary.
  /// If cloud secondary is ahead, pulls the changes to the local secondary.
  ///
  /// Register to onDone and onError callback. The callback accepts instance of [SyncResult].
  ///
  /// Sync process fails with exception when any of the below conditions met; The error is encapsulated in [SyncResult.atClientException]
  /// * If sync process is in-progress.
  /// * If Internet connection is down.
  /// * If cloud secondary is not reachable.
  ///
  /// Usage
  /// ```dart
  /// var syncService = SyncService(_atClient);
  ///
  /// syncService.sync(_onDoneCallback, _onErrorCallback);
  ///
  /// // Called when sync process is successful.
  /// void _onDoneCallback(syncResult){
  ///   print(syncResult.syncStatus);
  ///   print(syncResult.lastSyncedOn);
  /// }
  ///
  /// // Called when error occurs in sync process.
  /// void _onErrorCallback(syncResult){
  ///   print(syncResult.syncStatus);
  ///   print(syncResult.atClientException);
  /// }
  /// ```
  void sync({Function? onDone});

  /// Returns true if local and cloud secondary are in sync. false otherwise
  Future<bool> isInSync();
}
