import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';

///A [SyncManager] object is used to ensure data in local secondary(e.g mobile device) and cloud secondary are in sync.
class SyncManager {
  var _syncInProgress = false;

  String _atSign;

  var _regex;

  final _logger = AtSignLogger('SyncManager');

  static final Map<String, SyncManager> _syncManagerMap = {};

  factory SyncManager.getInstance(String atSign) {
    if (_syncManagerMap.containsKey(_syncManagerMap)) {
      return _syncManagerMap[atSign];
    }
    final syncManager = SyncManager._internal(atSign);
    _syncManagerMap[atSign] = syncManager;
    return syncManager;
  }

  SyncManager._internal(this._atSign);

  LocalSecondary localSecondary;

  RemoteSecondary remoteSecondary;

  AtClientPreference preference;

  /// Calling sync with [regex] will ensure only matching keys are synced.
  /// sync will be retried on any connection related errors.
  /// [onDone] callback is invoked when sync completes successfully.
  /// e.g onDone callback
  /// ```
  /// void onDone(SyncManager syncManager) {
  ///  // add your sync completion logic
  /// }
  /// ```
  /// Call isSyncInProgress to know if the sync is completed or if it is still in progress.
  Future<void> sync(Function onDone, {String regex}) async {
    // Return is there is any sync already in progress
    _regex = regex;
    await _sync(onDone, _onError, regex: _regex);
    return;
  }

  Future<void> _sync(Function onDone, Function onError, {String regex}) async {
    await syncOnce(onDone, _onError, regex: _regex);
  }

  void _done(var syncManager) {
    _logger.finer('sync complete');
  }

  void _onError(var syncManager, Exception e) {
    if (e is AtConnectException) {
      Future.delayed(
          Duration(seconds: 3), () => _sync(_done, _onError, regex: _regex));
    } else {
      _logger.finer('Error in sync : ${e.toString()}');
    }
  }

  /// Initiates a Sync with the server. If the sync encounters any exceptions
  /// [onError] call back is called and the Sync is terminated.
  /// e.g onError callback
  /// ```
  /// void onError(SyncManagar syncManager, Exception e) {
  /// // add your sync error logic
  /// }
  /// ```
  /// [onDone] callback is called if the sync completes successfully.
  /// e.g onDone callback
  /// ```
  /// void onDone(SyncManager syncManager) {
  /// // add your sync completion logic
  /// }
  /// ```
  /// Optionally pass [regex] to sync only matching keys.
  Future<void> syncOnce(Function onDone, Function onError,
      {String regex}) async {
    if (_syncInProgress) {
      _logger.finer('Another Sync process is in progress.');
      return;
    }
    _syncInProgress = true;
    try {
      await _checkConnectivity();
      var syncObject = await _getSyncObject(regex: regex);
      var lastSyncedCommitId = syncObject.lastSyncedCommitId;
      var serverCommitId = syncObject.serverCommitId;
      var isInSync = SyncUtil.isInSync(syncObject.uncommittedEntries,
          syncObject.serverCommitId, syncObject.lastSyncedCommitId);
      if (isInSync) {
        _logger.finer('Server and local secondary are in sync');
        _syncInProgress = false;
        return;
      }
      lastSyncedCommitId ??= -1;
      serverCommitId ??= -1;
      syncObject.lastSyncedCommitId ??= -1;
      if (serverCommitId > lastSyncedCommitId) {
        //pull changes from cloud to local
        await _pullChanges(syncObject, regex: regex);
      }
      //push changes from local to cloud
      await _pushChanges(syncObject, regex: regex);
      _syncInProgress = false;
      onDone(this);
    } on Exception catch (e) {
      _syncInProgress = false;
      onError(this, e);
    }
  }

  Future<void> _pullChanges(SyncObject syncObject, {String regex}) async {
    var syncResponse = await remoteSecondary.sync(syncObject.lastSyncedCommitId, _syncLocal,
        regex: regex);
    if (syncResponse != null && syncResponse != 'data:null') {
      syncResponse = syncResponse.replaceFirst('data:', '');
      var syncResponseJson = jsonDecode(syncResponse);
      await Future.forEach(syncResponseJson,
              (serverCommitEntry) => _syncLocal(serverCommitEntry));
    }
  }

  Future<void> _pushChanges(SyncObject syncObject, {String regex}) async {
    var uncommittedEntryBatch =
        _getUnCommittedEntryBatch(syncObject.uncommittedEntries);
    for (var unCommittedEntryList in uncommittedEntryBatch) {
      var batchRequests = await _getBatchRequests(unCommittedEntryList);
      var batchResponse = await _sendBatch(batchRequests);
      for (var entry in batchResponse) {
        try {
          var batchId = entry['id'];
          var serverResponse = entry['response'];
          var responseObject = Response.fromJson(serverResponse);
          var commitId = -1;
          if (responseObject.data != null) {
            commitId = int.parse(responseObject.data);
          }
          var commitEntry = unCommittedEntryList.elementAt(batchId - 1);
          if (commitId == -1) {
            _logger.severe(
                'update/delete for key ${commitEntry.atKey} failed. Error code ${responseObject.errorCode} error message ${responseObject.errorMessage}');
          }

          _logger.finer('***batchId:$batchId key: ${commitEntry.atKey}');
          await SyncUtil.updateCommitEntry(commitEntry, commitId, _atSign);
        } on Exception catch (e) {
          //entire batch should not fail.So handle any exception
          _logger.severe(
              'exception while updating commit entry for entry:$entry ${e.toString()}');
        }
      }
    }
  }

  Future<void> _syncLocal(serverCommitEntry) async {
    switch (serverCommitEntry['operation']) {
      case '+':
      case '#':
      case '*':
        var builder = UpdateVerbBuilder()
          ..atKey = serverCommitEntry['atKey']
          ..value = serverCommitEntry['value'];
        builder.operation = UPDATE_ALL;
        _setMetaData(builder, serverCommitEntry);
        await _pullToLocal(builder, serverCommitEntry, CommitOp.UPDATE_ALL);
        break;
      case '-':
        var builder = DeleteVerbBuilder()..atKey = serverCommitEntry['atKey'];
        await _pullToLocal(builder, serverCommitEntry, CommitOp.DELETE);
        break;
    }
  }

  Future<bool> isInSync({String regex}) async {
    await _checkConnectivity();
    var syncObject = await _getSyncObject(regex: regex);
    var isInSync = SyncUtil.isInSync(syncObject.uncommittedEntries,
        syncObject.serverCommitId, syncObject.lastSyncedCommitId);
    return isInSync;
  }

  Future<SyncObject> _getSyncObject({String regex}) async {
    var lastSyncedEntry =
        await SyncUtil.getLastSyncedEntry(regex, atSign: _atSign);
    var lastSyncedCommitId = lastSyncedEntry?.commitId;
    var serverCommitId =
        await SyncUtil.getLatestServerCommitId(remoteSecondary, regex);
    var lastSyncedLocalSeq = lastSyncedEntry != null ? lastSyncedEntry.key : -1;
    var unCommittedEntries = await SyncUtil.getChangesSinceLastCommit(
        lastSyncedLocalSeq, regex,
        atSign: _atSign);
    return SyncObject()
      ..uncommittedEntries = unCommittedEntries
      ..serverCommitId = serverCommitId
      ..lastSyncedCommitId = lastSyncedCommitId;
  }

  Future<void> _checkConnectivity() async {
    if (!(await NetworkUtil.isNetworkAvailable())) {
      throw AtConnectException('Internet connection unavailable to sync');
    }
    if (!(await remoteSecondary.isAvailable())) {
      throw AtConnectException('Secondary server is unavailable');
    }
  }

  Future<void> _pullToLocal(
      VerbBuilder builder, serverCommitEntry, CommitOp operation) async {
    var verbResult = await localSecondary.executeVerb(builder, sync: false);
    var sequenceNumber = int.parse(verbResult.split(':')[1]);
    var commitEntry = await SyncUtil.getCommitEntry(sequenceNumber, _atSign);
    commitEntry.operation = operation;
    await SyncUtil.updateCommitEntry(
        commitEntry, serverCommitEntry['commitId'], _atSign);
  }

  void _setMetaData(builder, serverCommitEntry) {
    var metaData = serverCommitEntry['metadata'];
    if (metaData != null && metaData.isNotEmpty) {
      if (metaData[AT_TTL] != null) builder.ttl = int.parse(metaData[AT_TTL]);
      if (metaData[AT_TTB] != null) builder.ttb = int.parse(metaData[AT_TTB]);
      if (metaData[AT_TTR] != null) builder.ttr = int.parse(metaData[AT_TTR]);
      if (metaData[CCD] != null) {
        (metaData[CCD].toLowerCase() == 'true')
            ? builder.ccd = true
            : builder.ccd = false;
      }
      if (metaData[PUBLIC_DATA_SIGNATURE] != null) {
        builder.dataSignature = metaData[PUBLIC_DATA_SIGNATURE];
      }
      if (metaData[IS_BINARY] != null) {
        (metaData[IS_BINARY].toLowerCase() == 'true')
            ? builder.isBinary = true
            : builder.isBinary = false;
      }
      if (metaData[IS_ENCRYPTED] != null) {
        (metaData[IS_ENCRYPTED].toLowerCase() == 'true')
            ? builder.isEncrypted = true
            : builder.isEncrypted = false;
      }
    }
  }

  List<dynamic> _getUnCommittedEntryBatch(
      List<CommitEntry> uncommittedEntries) {
    var unCommittedEntryBatch = [];
    var batchSize = preference.syncBatchSize, i = 0;
    var totalEntries = uncommittedEntries.length;
    var totalBatch = (totalEntries % batchSize == 0)
        ? totalEntries / batchSize
        : (totalEntries / batchSize).floor() + 1;
    var startIndex = i;
    while (i < totalBatch) {
      var endIndex = startIndex + batchSize < totalEntries
          ? startIndex + batchSize
          : totalEntries;
      var currentBatch = uncommittedEntries.sublist(startIndex, endIndex);
      unCommittedEntryBatch.add(currentBatch);
      startIndex += batchSize;
      i++;
    }
    return unCommittedEntryBatch;
  }

  Future<List<BatchRequest>> _getBatchRequests(
      List<CommitEntry> uncommittedEntries) async {
    var batchRequests = <BatchRequest>[];
    var batchId = 1;
    for (var entry in uncommittedEntries) {
      var command = await _getCommand(entry);
      command = command.replaceAll('cached:', '');
      command = VerbUtil.replaceNewline(command);
      var batchRequest = BatchRequest(batchId, command);
      _logger.finer('batchId:$batchId key:${entry.atKey}');
      batchRequests.add(batchRequest);
      batchId++;
    }
    return batchRequests;
  }

  dynamic _sendBatch(List<BatchRequest> requests) async {
    var command = 'batch:';
    command += jsonEncode(requests);
    command += '\n';
    var verbResult = await remoteSecondary.executeCommand(command, auth: true);
    _logger.finer('batch result:$verbResult');
    if (verbResult != null) {
      verbResult = verbResult.replaceFirst('data:', '');
    }
    return jsonDecode(verbResult);
  }

  Future<String> _getCommand(CommitEntry entry) async {
    var command;
    switch (entry.operation) {
      case CommitOp.UPDATE:
        var key = entry.atKey;
        var value = await localSecondary.keyStore.get(key);
        command = 'update:$key ${value?.data}';
        break;
      case CommitOp.DELETE:
        var key = entry.atKey;
        command = 'delete:$key';
        break;
      case CommitOp.UPDATE_META:
        var key = entry.atKey;
        var metaData = await localSecondary.keyStore.getMeta(key);
        if (metaData != null) {
          key += _metadataToString(metaData);
        }
        command = 'update:meta:$key';
        break;
      case CommitOp.UPDATE_ALL:
        var key = entry.atKey;
        var value = await localSecondary.keyStore.get(key);
        var metaData = await localSecondary.keyStore.getMeta(key);
        var keyGen = '';
        if (metaData != null) {
          keyGen = _metadataToString(metaData);
        }
        keyGen += ':$key';
        value?.metaData = metaData;
        command = 'update$keyGen ${value?.data}';
        break;
    }
    return command;
  }

  String _metadataToString(dynamic metadata) {
    var metadataStr = '';
    if (metadata.ttl != null) metadataStr += ':ttl:${metadata.ttl}';
    if (metadata.ttb != null) metadataStr += ':ttb:${metadata.ttb}';
    if (metadata.ttr != null) metadataStr += ':ttr:${metadata.ttr}';
    if (metadata.isCascade != null) {
      metadataStr += ':ccd:${metadata.isCascade}';
    }
    if (metadata.dataSignature != null) {
      metadataStr += ':dataSignature:${metadata.dataSignature}';
    }
    if (metadata.isBinary != null) {
      metadataStr += ':isBinary:${metadata.isBinary}';
    }
    if (metadata.isEncrypted != null) {
      metadataStr += ':isEncrypted:${metadata.isEncrypted}';
    }
    return metadataStr;
  }

  bool isSyncInProgress() {
    return _syncInProgress;
  }
}

class SyncObject {
  List<CommitEntry> uncommittedEntries;
  int serverCommitId;
  int lastSyncedCommitId;
}
