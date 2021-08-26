import 'dart:async';
import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';

///A [SyncService] object is used to ensure data in local secondary(e.g mobile device) and cloud secondary are in sync.
class SyncServiceImpl implements SyncService, AtSignChangeListener {
  bool _isSyncInProgress = false;
  late final AtClient _atClient;
  var _serverCommitId;
  var _lastServerCommitIdDateTime;
  late final RemoteSecondary _remoteSecondary;
  late final NotificationServiceImpl _statsNotificationListener;
  static const LIMIT = 10;
  static final Map<String, SyncService> _syncServiceMap = {};

  final _logger = AtSignLogger('SyncService');

  static SyncService create(AtClient atClient) {
    if (_syncServiceMap.containsKey(atClient.getCurrentAtSign())) {
      return _syncServiceMap[atClient.getCurrentAtSign()]!;
    }
    final syncService = SyncServiceImpl._(atClient);
    _syncServiceMap[atClient.getCurrentAtSign()!] = syncService;
    return _syncServiceMap[atClient.getCurrentAtSign()]!;
  }

  SyncServiceImpl._(this._atClient) {
    _remoteSecondary = RemoteSecondary(
        _atClient.getCurrentAtSign()!, _atClient.getPreferences()!);
    AtClientManager.getInstance().listenToAtSignChange(this);
  }

  Future<SyncResult> sync({Function? onDone, Function? onError}) async {
    SyncResult syncResult;
    // If sync in-progress, return.
    if (_isSyncInProgress) {
      _logger.info('Sync already in-progress. Cannot start a new sync');
      syncResult = SyncResult();
      syncResult.syncStatus = SyncStatus.failure;
      syncResult.atClientException = AtClientException(
          'AT0014', 'Sync-InProgress. Cannot start a new sync process');
      if (onError != null) {
        onError(syncResult);
      }
      return syncResult;
    }
    try {
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
        if (onError != null) {
          onError(syncResult);
        }
        return syncResult;
      }
      var serverCommitId;
      try {
        // Check if local and cloud secondary are in sync. If true, return.
        if (await isInSync()) {
          syncResult = SyncResult();
          _logger.info('Local Secondary and Cloud Secondary are in sync');
          // Setting isSyncInProgress to false, to allow next sync call.
          _isSyncInProgress = false;
          if (onDone != null) {
            onDone(syncResult);
          }
          return syncResult;
        }
        // Get latest server commit id.
        serverCommitId = await _getServerCommitId();
      } on AtLookUpException catch (exception) {
        _logger.severe(
            '${_atClient.getCurrentAtSign()} ${exception.errorMessage}');
        syncResult = SyncResult();
        syncResult.syncStatus = SyncStatus.failure;
        syncResult.atClientException =
            AtClientException(exception.errorCode, exception.errorMessage);
        // Setting isSyncInProgress to false, to allow next sync call.
        _isSyncInProgress = false;
        if (onError != null) {
          onError(syncResult);
        }
        return syncResult;
      }
      // Sync
      return await _sync(serverCommitId, onDone, onError);
    } finally {
      _isSyncInProgress = false;
    }
  }

  Future<SyncResult> _sync(
      int serverCommitId, Function? onDone, Function? onError) async {
    var syncResult = SyncResult();
    var localCommitId = await _getLocalCommitId();
    try {
      _logger.finer('Sync in progress');
      if (serverCommitId > localCommitId) {
        _logger.finer('syncing to local');
        await _syncFromServer(serverCommitId, localCommitId);
        // Getting localCommitId to get the latest commit id after cloud secondary changes are
        // synced.
        localCommitId = await _getLocalCommitId();
      }
      var unCommittedEntries = await SyncUtil.getChangesSinceLastCommit(
          localCommitId, _atClient.getPreferences()!.syncRegex,
          atSign: _atClient.getCurrentAtSign()!);
      if (unCommittedEntries.isNotEmpty) {
        _logger.finer('syncing to remote');
        await _syncToRemote(unCommittedEntries);
      }
      _isSyncInProgress = false;
      syncResult.lastSyncedOn = DateTime.now().toUtc();
      if (onDone != null) {
        onDone(syncResult);
      }
    } on Exception catch (e) {
      syncResult.atClientException = AtClientException(
          at_client_error_codes['SyncException'], e.toString());
      syncResult.syncStatus = SyncStatus.failure;
      _isSyncInProgress = false;
      if (onError != null) {
        onError(syncResult);
      }
    }
    return syncResult;
  }


  /// Syncs the local entries to cloud secondary.
  Future<void> _syncToRemote(List<CommitEntry> unCommittedEntries) async {
    var uncommittedEntryBatch = _getUnCommittedEntryBatch(unCommittedEntries);
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
              _logger.severe(
                  'update/delete for key ${commitEntry.atKey} failed. Error code ${responseObject.errorCode} error message ${responseObject.errorMessage}');
            }

            _logger.finer('***batchId:$batchId key: ${commitEntry.atKey}');
            await SyncUtil.updateCommitEntry(
                commitEntry, commitId, _atClient.getCurrentAtSign()!);
          } on Exception catch (e) {
            _logger.severe(
                'exception while updating commit entry for entry:$entry ${e.toString()}');
          }
        }
      } on Exception catch (e) {
        _logger.severe(
            'exception while syncing batch: ${e.toString()} batch commit entries: $unCommittedEntryList');
      }
    }
  }

  /// Syncs the cloud secondary changes to local secondary.
  Future<void> _syncFromServer(int serverCommitId, int localCommitId) async {
    // Iterates until serverCommitId and localCommitId are equal.
    while (serverCommitId != localCommitId) {
      var syncBuilder = SyncVerbBuilder()
        ..commitId = localCommitId
        ..regex = _atClient.getPreferences()!.syncRegex
        ..limit = LIMIT
        ..isPaginated = true;
      var syncResponse = DefaultResponseParser()
          .parse(await _remoteSecondary.executeVerb(syncBuilder));
      var syncResponseJson = jsonDecode(syncResponse.response);
      // Iterates over each commit
      await Future.forEach(syncResponseJson,
          (dynamic serverCommitEntry) => _syncLocal(serverCommitEntry));
      // assigning the lastSynced local commit id.
      localCommitId = await _getLocalCommitId();
    }
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

  Future<String> _getCommand(CommitEntry entry) async {
    late var command;
    // ignore: missing_enum_constant_in_switch
    switch (entry.operation) {
      case CommitOp.UPDATE:
        var key = entry.atKey;
        var value = await _atClient.getLocalSecondary()!.keyStore!.get(key);
        command = 'update:$key ${value?.data}';
        break;
      case CommitOp.DELETE:
        var key = entry.atKey;
        command = 'delete:$key';
        break;
      case CommitOp.UPDATE_META:
        var key = entry.atKey;
        var metaData =
            await _atClient.getLocalSecondary()!.keyStore!.getMeta(key);
        if (metaData != null) {
          key = '$key$_metadataToString(metaData)';
        }
        command = 'update:meta:$key';
        break;
      case CommitOp.UPDATE_ALL:
        var key = entry.atKey;
        var value = await _atClient.getLocalSecondary()!.keyStore!.get(key);
        var metaData =
            await _atClient.getLocalSecondary()!.keyStore!.getMeta(key);
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

  ///Verifies if local secondary are cloud secondary are in sync.
  ///Returns true if local secondary and cloud secondary are in sync; else false.
  ///Throws [AtLookUpException] if cloud secondary is not reachable
  Future<bool> isInSync() async {
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
  Future<int> _getServerCommitId({bool getFromServer = false}) async {
    if (_serverCommitId == null ||
        getFromServer ||
        (_lastServerCommitIdDateTime != null &&
            DateTime.now()
                    .toUtc()
                    .difference(_lastServerCommitIdDateTime)
                    .inMinutes >
                5)) {
      _logger.finer('Getting server commit Id from cloud secondary');
      _serverCommitId = await SyncUtil.getLatestServerCommitId(
          _atClient.getRemoteSecondary()!,
          _atClient.getPreferences()!.syncRegex);
    }
    // If server commit id is null, set to -1;
    _serverCommitId ??= -1;
    return _serverCommitId;
  }

  /// Listens on stats notification sent by the cloud secondary server
  void _statsServiceListener() {
    _statsNotificationListener =
        NotificationServiceImpl.create(_atClient) as NotificationServiceImpl;
    // Setting the regex to 'statsNotification' to receive only the notifications
    // from stats notification service.
    _statsNotificationListener
        .subscribe(regex: 'statsNotification')
        .listen((notification) {
      _serverCommitId = notification.value;
      _lastServerCommitIdDateTime =
          DateTime.fromMillisecondsSinceEpoch(notification.epochMillis);
    });
  }

  /// Returns the local commit id. If null, returns -1.
  Future<int> _getLocalCommitId() async {
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
    return localCommitId;
  }

  dynamic _sendBatch(List<BatchRequest> requests) async {
    var command = 'batch:';
    command += jsonEncode(requests);
    command += '\n';
    var verbResult = await _atClient
        .getRemoteSecondary()!
        .executeCommand(command, auth: true);
    _logger.finer('batch result:$verbResult');
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

  List<dynamic> _getUnCommittedEntryBatch(
      List<CommitEntry?> uncommittedEntries) {
    var unCommittedEntryBatch = [];
    var batchSize = _atClient.getPreferences()!.syncBatchSize, i = 0;
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
    var verbResult =
        await _atClient.getLocalSecondary()!.executeVerb(builder, sync: false);
    if (verbResult == null) {
      return;
    }
    var sequenceNumber = int.parse(verbResult.split(':')[1]);
    var commitEntry = await (SyncUtil.getCommitEntry(
        sequenceNumber, _atClient.getCurrentAtSign()!));
    if (commitEntry == null) {
      return;
    }
    commitEntry.operation = operation;
    await SyncUtil.updateCommitEntry(commitEntry, serverCommitEntry['commitId'],
        _atClient.getCurrentAtSign()!);
  }

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    if (switchAtSignEvent.previousAtClient?.getCurrentAtSign() ==
        _atClient.getCurrentAtSign()) {
      // actions for previous atSign
      _logger.finer(
          'stopping monitor and listeners for ${_atClient.getCurrentAtSign()}');
      _statsNotificationListener.stopAllSubscriptions();
    } else {
      // actions for new atSign
      _logger.finer(
          'starting monitor and stats listener for ${_atClient.getCurrentAtSign()}');
      _statsServiceListener();
    }
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
