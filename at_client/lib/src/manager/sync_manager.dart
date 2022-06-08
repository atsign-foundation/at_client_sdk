import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/manager/sync_isolate_manager.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:cron/cron.dart';

/// [Deprecate] Use [SyncService]
@Deprecated("Use SyncService.Sync")
class SyncManager {
  var logger = AtSignLogger('SyncManager');

  LocalSecondary? _localSecondary;

  RemoteSecondary? _remoteSecondary;

  AtClientPreference? _preference;

  String? _atSign;

  bool isSyncInProgress = false;

  bool pendingSyncExists = false;

  var _isScheduled = false;

  SyncUtil? syncUtil;

  SyncManager(this._atSign);

  void init(String atSign, AtClientPreference preference,
      RemoteSecondary? _remoteSecondary, LocalSecondary? _localSecondary) {
    _atSign = atSign;
    _preference = preference;
    this._localSecondary = _localSecondary;
    this._remoteSecondary = RemoteSecondary(atSign, _preference!,
        privateKey: _preference!.privateKey);
    if (preference.syncStrategy == SyncStrategy.scheduled && !_isScheduled) {
      _scheduleSyncTask();
    }
    syncUtil = SyncUtil();
  }

  @Deprecated("Use SyncService.isInSync")
  Future<bool> isInSync() async {
    var serverCommitId = await SyncUtil.getLatestServerCommitId(
        _remoteSecondary!, _preference!.syncRegex);
    var lastSyncedEntry = await syncUtil
        ?.getLastSyncedEntry(_preference!.syncRegex, atSign: _atSign!);
    var lastSyncedCommitId = lastSyncedEntry?.commitId;
    var lastSyncedLocalSeq = lastSyncedEntry != null ? lastSyncedEntry.key : -1;
    var unCommittedEntries = await syncUtil?.getChangesSinceLastCommit(
        lastSyncedLocalSeq, _preference!.syncRegex,
        atSign: _atSign!);
    return SyncUtil.isInSync(
        unCommittedEntries, serverCommitId, lastSyncedCommitId);
  }

  /// Cloud Secondary server throws [BufferOverFlowException] is sync data is large than the buffer size.
  /// Optionally isStream when set to true, initiates the sync process via streams which facilitates in
  /// syncing large data without [BufferOverFlowException].
  /// [Deprecated] Use [SyncService]
  @Deprecated("Use SyncService.sync")
  Future<void> sync({bool appInit = false, String? regex}) async {
    //initially isSyncInProgress and pendingSyncExists are false.
    //If a new sync triggered while previous sync isInprogress,then pendingSyncExists set to true and returns.
    if (isSyncInProgress) {
      pendingSyncExists = true;
      return;
    }
    regex ??= _preference!.syncRegex;
    await _sync(appInit: appInit, regex: regex);
    //once the sync done, we will check for any new sync requests(pendingSyncExists == true)
    //If pendingSyncExists is true,then sync triggers again.
    if (pendingSyncExists) {
      pendingSyncExists = false;
      return sync(appInit: appInit, regex: regex);
    }
    return;
  }

  Future<void> _sync({bool appInit = false, String? regex}) async {
    try {
      regex ??= _preference!.syncRegex;
      //isSyncProgress set to true during the sync is in progress.
      //once sync process done, it will again set to false.
      isSyncInProgress = true;
      var lastSyncedEntry =
          await syncUtil?.getLastSyncedEntry(regex, atSign: _atSign!);
      var lastSyncedCommitId = lastSyncedEntry?.commitId;
      var serverCommitId =
          await SyncUtil.getLatestServerCommitId(_remoteSecondary!, regex);
      var lastSyncedLocalSeq =
          lastSyncedEntry != null ? lastSyncedEntry.key : -1;
      if (appInit && lastSyncedLocalSeq > 0) {
        serverCommitId ??= -1;
        if (lastSyncedLocalSeq > serverCommitId) {
          lastSyncedLocalSeq = serverCommitId;
        }
        logger.finer('app init: lastSyncedLocalSeq: $lastSyncedLocalSeq');
      }
      var unCommittedEntries = await syncUtil?.getChangesSinceLastCommit(
          lastSyncedLocalSeq, regex,
          atSign: _atSign!);
      // cloud and local are in sync if there is no synced changes in local and commitIDs are equals
      if (SyncUtil.isInSync(
          unCommittedEntries, serverCommitId, lastSyncedCommitId)) {
        logger.info('server and local is in sync');
        return;
      }
      lastSyncedCommitId ??= -1;
      serverCommitId ??= -1;
      // cloud is ahead if server commit id is > last synced commit id in local
      if (serverCommitId > lastSyncedCommitId) {
        // Iterates until serverCommitId is greater than localCommitId are equal.
        while (serverCommitId > lastSyncedCommitId!) {
          var syncBuilder = SyncVerbBuilder()
            ..commitId = lastSyncedCommitId
            ..regex = regex;
          // ignore: prefer_typing_uninitialized_variables
          var syncResponse;
          try {
            syncResponse = await _remoteSecondary!.executeVerb(syncBuilder);
          } on AtClientException catch (e) {
            logger.severe(
                'Exception occurred in processing sync command ${e.message}');
          }
          if (syncResponse.isNotEmpty && syncResponse != 'data:null') {
            syncResponse = syncResponse.replaceFirst('data:', '');
            var syncResponseJson = JsonUtils.decodeJson(syncResponse);
            // Iterates over each commit
            await Future.forEach(syncResponseJson,
                (dynamic serverCommitEntry) => _syncLocal(serverCommitEntry));
          }
          // assigning the lastSynced local commit id.
          var lastSyncedEntry =
              await syncUtil?.getLastSyncedEntry(regex, atSign: _atSign!);
          lastSyncedCommitId = lastSyncedEntry?.commitId;
        }
        return;
      }

      // local is ahead. push the changes to secondary server
      var uncommittedEntryBatch =
          _getUnCommittedEntryBatch(unCommittedEntries!);
      for (var unCommittedEntryList in uncommittedEntryBatch) {
        try {
          var batchRequests = await _getBatchRequests(unCommittedEntryList);
          var batchResponse = await _sendBatch(batchRequests);
          for (var entry in batchResponse) {
            try {
              var batchId = entry['id'];
              var serverResponse = entry['response'];
              var responseObject = Response.fromJson(serverResponse);
              var commitId = -1;
              if (responseObject.data != null) {
                commitId = int.parse(responseObject.data!);
              }
              var commitEntry = unCommittedEntryList.elementAt(batchId - 1);
              if (commitId == -1) {
                logger.severe(
                    'update/delete for key ${commitEntry.atKey} failed. Error code ${responseObject.errorCode} error message ${responseObject.errorMessage}');
              }

              logger.finer('***batchId:$batchId key: ${commitEntry.atKey}');
              await syncUtil?.updateCommitEntry(
                  commitEntry, commitId, _atSign!);
            } on Exception catch (e) {
              logger.severe(
                  'exception while updating commit entry for entry:$entry ${e.toString()}');
            }
          }
        } on Exception catch (e) {
          logger.severe(
              'exception while syncing batch: ${e.toString()} batch commit entries: $unCommittedEntryList');
        }
      }
    } on AtLookUpException catch (e) {
      if (e.errorCode == 'AT0021') {
        logger.info('skipping sync since secondary is not reachable');
      }
    } finally {
      isSyncInProgress = false;
    }
  }

  Future<void> syncWithIsolate() async {
    var lastSyncedEntry = await syncUtil
        ?.getLastSyncedEntry(_preference!.syncRegex, atSign: _atSign!);
    var lastSyncedCommitId = lastSyncedEntry?.commitId;
    var commitIdReceivePort = ReceivePort();
    var privateKey = await _localSecondary!.keyStore!.get(AT_PKAM_PRIVATE_KEY);
    var isolate = await Isolate.spawn(
        SyncIsolateManager.executeRemoteCommandIsolate,
        commitIdReceivePort.sendPort);
    var syncDone = false;
    dynamic syncSendPort;
    dynamic pushedCount;
    commitIdReceivePort.listen((message) async {
      if (syncSendPort == null && message is SendPort) {
        //1. Request to isolate to get latest server commit id from server
        syncSendPort = message;
        logger.info('sending:');
        var isolateInput = <String, dynamic>{};
        isolateInput['operation'] = 'get_commit_id';
        isolateInput['atsign'] = _atSign;
        isolateInput['preference'] = _preference;
        isolateInput['private_key'] = privateKey?.data;
        syncSendPort.send(isolateInput);
      } else {
        logger.info('received server commit id from isolate: $message');
        var operation = message['operation'];
        switch (operation) {
          case 'get_commit_id_result':
            // 1.1 commit id response from isolate
            var serverCommitId = message['commit_id'];
            var lastSyncedLocalSeq =
                lastSyncedEntry != null ? lastSyncedEntry.key : -1;
            var unCommittedEntries = await syncUtil?.getChangesSinceLastCommit(
                lastSyncedLocalSeq, _preference!.syncRegex!,
                atSign: _atSign!);
            if (SyncUtil.isInSync(
                unCommittedEntries, serverCommitId, lastSyncedCommitId)) {
              logger.info('server and local is in sync');
              syncDone = true;
            }
            lastSyncedCommitId ??= -1;
            serverCommitId ??= -1;
            var isolateInput = <String, dynamic>{};
            isolateInput['atsign'] = _atSign;
            isolateInput['preference'] = _preference;
            if (serverCommitId > lastSyncedCommitId) {
              //2. server is ahead
              //2.1 Send last synced id to isolate to get latest changes from server
              isolateInput['operation'] = 'get_server_commits';
              isolateInput['last_synced_commit_id'] = lastSyncedCommitId;
              syncSendPort.send(isolateInput);
            } else {
              //3. local is ahead
              //3.1 For each uncommitted entry send request to isolate to send update/delete to server
              pushedCount = unCommittedEntries!.length;
              for (var entry in unCommittedEntries) {
                var command = await _getCommand(entry);
                logger.info('command:$command');
                dynamic builder;
                switch (entry.operation) {
                  case CommitOp.UPDATE:
                    builder = UpdateVerbBuilder.getBuilder(command);
                    break;
                  case CommitOp.DELETE:
                    builder = DeleteVerbBuilder.getBuilder(command);
                    break;
                  case CommitOp.UPDATE_META:
                    builder = UpdateVerbBuilder.getBuilder(command);
                    break;
                  case CommitOp.UPDATE_ALL:
                    builder = UpdateVerbBuilder.getBuilder(command);
                    break;
                  default:
                    break;
                }
                isolateInput['operation'] = 'push_to_remote';
                isolateInput['builder'] = builder;
                isolateInput['entry_key'] = entry.key;
                syncSendPort.send(isolateInput);
                sleep(Duration(
                    seconds:
                        1)); // workaround for receiving out of order response from message listener
              }
            }
            break;
          case 'get_server_commits_result':
            //2.2 Sync verb response from isolate. For each entry sync to local storage and update commit id.
            var syncResponse = message['sync_response'];
            var syncResponseJson = jsonDecode(syncResponse);
            await Future.forEach(syncResponseJson,
                (dynamic serverCommitEntry) => _syncLocal(serverCommitEntry));
            syncDone = true;
            break;
          case 'push_to_remote_result':
            // 3.2 Update/delete verb commit id response from server. Update server commit id in local commit log.
            var serverCommitId = message['operation_commit_id'];
            dynamic entryKey = message['entry_key'];
            var entry = SyncUtil.getEntry(entryKey, _atSign!);
            logger.info(
                'received remote push result: $entryKey $entry $entryKey');
            await syncUtil?.updateCommitEntry(
                entry, int.parse(serverCommitId), _atSign!);
            pushedCount--;
            if (pushedCount == 0) syncDone = true;
            break;
        }
        if (syncDone) {
          // 2.3 server ahead sync done
          // 3.3 local ahead sync done
          isolate.kill(priority: Isolate.immediate);
          logger.info('isolate sync complete');
          return;
        }
      }
    });
  }

  dynamic _sendBatch(List<BatchRequest> requests) async {
    var command = 'batch:';
    command += jsonEncode(requests);
    command += '\n';
    var verbResult =
        await _remoteSecondary!.executeCommand(command, auth: true);
    logger.finer('batch result:$verbResult');
    if (verbResult != null) {
      verbResult = verbResult.replaceFirst('data:', '');
    }
    return jsonDecode(verbResult!);
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

  Future<void> _pullToLocal(
      VerbBuilder builder, serverCommitEntry, CommitOp operation) async {
    var verbResult = await _localSecondary!.executeVerb(builder, sync: false);
    if (verbResult == null) {
      return;
    }
    var sequenceNumber = int.parse(verbResult.split(':')[1]);
    var commitEntry = await (SyncUtil.getCommitEntry(sequenceNumber, _atSign!));
    if (commitEntry == null) {
      return;
    }
    commitEntry.operation = operation;
    await syncUtil?.updateCommitEntry(
        commitEntry, serverCommitEntry['commitId'], _atSign!);
  }

  Future<void> syncImmediate(
      String localSequence, VerbBuilder builder, CommitOp? operation) async {
    try {
      var verbResult = await _remoteSecondary!.executeVerb(builder);
      var serverCommitId = verbResult.split(':')[1];
      var localCommitEntry =
          await (SyncUtil.getCommitEntry(int.parse(localSequence), _atSign!));
      if (localCommitEntry == null) {
        return;
      }
      localCommitEntry.operation = operation;
      await syncUtil?.updateCommitEntry(
          localCommitEntry, int.parse(serverCommitId), _atSign!);
    } on SecondaryConnectException {
      logger.severe('Unable to connect to secondary');
    }
  }

  Future<String> _getCommand(CommitEntry entry) async {
    late String command;
    // ignore: missing_enum_constant_in_switch
    switch (entry.operation) {
      case CommitOp.UPDATE:
        var key = entry.atKey;
        var value = await _localSecondary!.keyStore!.get(key);
        command = 'update:$key ${value?.data}';
        break;
      case CommitOp.DELETE:
        var key = entry.atKey;
        command = 'delete:$key';
        break;
      case CommitOp.UPDATE_META:
        var key = entry.atKey;
        var metaData = await _localSecondary!.keyStore!.getMeta(key);
        if (metaData != null) {
          key = '$key$_metadataToString(metaData)';
        }
        command = 'update:meta:$key';
        break;
      case CommitOp.UPDATE_ALL:
        var key = entry.atKey;
        var value = await _localSecondary!.keyStore!.get(key);
        var metaData = await _localSecondary!.keyStore!.getMeta(key);
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

  List<dynamic> _getUnCommittedEntryBatch(
      List<CommitEntry?> uncommittedEntries) {
    var unCommittedEntryBatch = [];
    var batchSize = _preference!.syncBatchSize, i = 0;
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
      logger.finer('batchId:$batchId key:${entry.atKey}');
      batchRequests.add(batchRequest);
      batchId++;
    }
    return batchRequests;
  }

  void _scheduleSyncTask() {
    var cron = Cron();
    cron.schedule(Schedule.parse('*/${_preference!.syncIntervalMins} * * * *'),
        () async {
      await syncWithIsolate();
    });
    _isScheduled = true;
  }
}
