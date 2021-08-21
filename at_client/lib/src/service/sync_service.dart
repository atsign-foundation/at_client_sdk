import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';

///A [SyncService] object is used to ensure data in local secondary(e.g mobile device) and cloud secondary are in sync.
class SyncService {
  bool _isSyncInProgress = false;
  final AtClient _atClient;

  final _logger = AtSignLogger('SyncService');

  SyncService(this._atClient);

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
  Future<void> sync(Function onDone, Function onError) async {
    SyncResult syncResult;
    // If sync in-progress, return.
    if (_isSyncInProgress) {
      _logger.info('Sync already in-progress. Cannot start a new sync');
      syncResult = SyncResult();
      syncResult.syncStatus = SyncStatus.failure;
      syncResult.atClientException = AtClientException(
          'AT0014', 'Sync-InProgress. Cannot start a new sync process');
      onError(syncResult);
      return;
    }
    //Setting isSyncInProgress to true to prevent parallel sync calls.
    _isSyncInProgress = true;
    // If network is not available, return.
    if (!await NetworkUtil.isNetworkAvailable()) {
      _logger.severe('Failed connecting to internet');
      syncResult = SyncResult();
      syncResult.syncStatus = SyncStatus.failure;
      syncResult.atClientException =
          AtClientException('AT0014', 'Failed connecting to internet');
      _isSyncInProgress = false;
      onError(syncResult);
      return;
    }
    var serverCommitId;
    try {
      // Check if local and cloud secondary are in sync. If true, return.
      if (await _isInSync()) {
        syncResult = SyncResult();
        _logger.info('Local Secondary and Cloud Secondary are in sync');
        // Setting isSyncInProgress to false, to allow next sync call.
        _isSyncInProgress = false;
        onDone(syncResult);
        return;
      }
      // Get latest server commit id.
      serverCommitId = await _getServerCommitId();
    } on AtLookUpException catch (exception) {
      _logger
          .severe('${_atClient.getCurrentAtSign()} ${exception.errorMessage}');
      syncResult = SyncResult();
      syncResult.syncStatus = SyncStatus.failure;
      syncResult.atClientException =
          AtClientException(exception.errorCode, exception.errorMessage);
      // Setting isSyncInProgress to false, to allow next sync call.
      _isSyncInProgress = false;
      onError(syncResult);
      return;
    }
    // Get lastSynced local commit id.
    var lastSyncEntry = await SyncUtil.getLastSyncedEntry(
        _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    var localCommitId;
    // If lastSyncEntry not null, set localCommitId to lastSyncedEntry.commitId
    // Else set to -1.
    (lastSyncEntry != null)
        ? localCommitId = lastSyncEntry.commitId
        : localCommitId = -1;
    // Sync
    _sync(serverCommitId, localCommitId, onDone, onError);
  }

  void _sync(int serverCommitId, int localCommitId, Function onDone,
      Function onError) {
    //Set isSyncInProgress to false to allow next sync process.
    print('Sync in progress');
    _isSyncInProgress = false;
  }

  ///Verifies if local secondary are cloud secondary are in sync.
  ///Returns true if local secondary and cloud secondary are in sync; else false.
  ///Throws [AtLookUpException] if cloud secondary is not reachable
  Future<bool> _isInSync() async {
    var serverCommitId = await _getServerCommitId();
    var lastSyncedEntry = await SyncUtil.getLastSyncedEntry(
        _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    var lastSyncedCommitId = lastSyncedEntry?.commitId;
    var lastSyncedLocalSeq = lastSyncedEntry != null ? lastSyncedEntry.key : -1;
    var unCommittedEntries = await SyncUtil.getChangesSinceLastCommit(
        lastSyncedLocalSeq, _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    return SyncUtil.isInSync(
        unCommittedEntries, serverCommitId, lastSyncedCommitId);
  }

  /// Returns the cloud secondary latest commit id. if null, returns -1.
  ///Throws [AtLookUpException] if secondary is not reachable
  Future<int> _getServerCommitId() async {
    var serverCommitId = await SyncUtil.getLatestServerCommitId(
        _atClient.getRemoteSecondary()!, _atClient.getPreferences()!.syncRegex);
    // If server commit id is null, set to -1;
    serverCommitId ??= -1;
    return serverCommitId;
  }
}

///Class to represent sync response.
class SyncResult {
  SyncStatus syncStatus = SyncStatus.success;
  AtClientException? atClientException;
  DateTime? lastSyncedOn;

  @override
  String toString() {
    return 'Sync status: $syncStatus lastSyncedOn: $lastSyncedOn Exception: $atClientException';
  }
}

///Enum to represent the sync status
enum SyncStatus { success, failure }
