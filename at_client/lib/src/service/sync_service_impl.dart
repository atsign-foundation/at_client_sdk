import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
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
import 'package:cron/cron.dart';
import 'package:uuid/uuid.dart';

///A [SyncService] object is used to ensure data in local secondary(e.g mobile device) and cloud secondary are in sync.
class SyncServiceImpl implements SyncService, AtSignChangeListener {
  static const _syncRequestThreshold = 3,
      _syncRequestTriggerInSeconds = 3,
      _syncRunIntervalSeconds = 5,
      _queueSize = 5;
  late final AtClient _atClient;
  late final RemoteSecondary _remoteSecondary;
  late final NotificationServiceImpl _statsNotificationListener;
  late final Cron _cron;
  final _syncRequests = ListQueue<SyncRequest>(_queueSize);
  static final Map<String, SyncService> _syncServiceMap = {};
  bool _syncInProgress = false;

  @override
  bool get isSyncInProgress => _syncInProgress;

  Function? onDone;

  final _logger = AtSignLogger('SyncService');

  late AtClientManager _atClientManager;

  static Future<SyncService> create(AtClient atClient,
      {required AtClientManager atClientManager}) async {
    if (_syncServiceMap.containsKey(atClient.getCurrentAtSign())) {
      return _syncServiceMap[atClient.getCurrentAtSign()]!;
    }
    final syncService = SyncServiceImpl._(atClientManager, atClient);
    await syncService._statsServiceListener();
    syncService._scheduleSyncRun();
    _syncServiceMap[atClient.getCurrentAtSign()!] = syncService;
    return _syncServiceMap[atClient.getCurrentAtSign()]!;
  }

  SyncServiceImpl._(AtClientManager atClientManager, AtClient atClient) {
    _atClientManager = atClientManager;
    _atClient = atClient;
    _remoteSecondary = RemoteSecondary(
        _atClient.getCurrentAtSign()!, _atClient.getPreferences()!);
    _atClientManager.listenToAtSignChange(this);
  }

  void _scheduleSyncRun() {
    _cron = Cron();

    _cron.schedule(Schedule.parse('*/$_syncRunIntervalSeconds * * * * *'),
        () async {
      try {
        await _processSyncRequests();
      } on Exception catch (e, trace) {
        _logger.finest(trace);
        _logger.severe('exception while running process sync:  $e');
        _syncInProgress = false;
      }
    });
  }

  @override
  void sync({Function? onDone}) {
    final syncRequest = SyncRequest();
    syncRequest.onDone = onDone;
    syncRequest.requestSource = SyncRequestSource.app;
    syncRequest.requestedOn = DateTime.now().toUtc();
    syncRequest.result = SyncResult();
    _addSyncRequestToQueue(syncRequest);
    return;
  }

  /// Listens on stats notification sent by the cloud secondary server
  Future<void> _statsServiceListener() async {
    _statsNotificationListener = await NotificationServiceImpl.create(_atClient)
        as NotificationServiceImpl;
    // Setting the regex to 'statsNotification' to receive only the notifications
    // from stats notification service.
    _statsNotificationListener
        .subscribe(regex: 'statsNotification')
        .listen((notification) async {
      _logger.finer('got stats notification in sync: ${notification.value}');
      final serverCommitId = notification.value;
      if (serverCommitId != null &&
          int.parse(serverCommitId) > await _getLocalCommitId()) {
        final syncRequest = SyncRequest();
        syncRequest.onDone = _onDone;
        syncRequest.onError = _onError;
        syncRequest.requestSource = SyncRequestSource.system;
        syncRequest.requestedOn = DateTime.now().toUtc();
        syncRequest.result = SyncResult();
        _addSyncRequestToQueue(syncRequest);
      }
    });
  }

  Future<void> _processSyncRequests() async {
    _logger.finest('in _processSyncRequests');
    if (_syncInProgress) {
      _logger.finer('**** another sync in progress');
      return;
    }
    if (!await NetworkUtil.isNetworkAvailable()) {
      _logger.finer('skipping sync due to network unavailability');
      return;
    }
    if (_syncRequests.isEmpty ||
        (_syncRequests.length < _syncRequestThreshold &&
            (_syncRequests.isNotEmpty &&
                DateTime.now()
                        .toUtc()
                        .difference(_syncRequests.elementAt(0).requestedOn)
                        .inSeconds <
                    _syncRequestTriggerInSeconds))) {
      _logger.finest('skipping sync - queue length ${_syncRequests.length}');
      return;
    }
    final syncRequest = _getSyncRequest();
    try {
      if (await isInSync()) {
        _logger.finer('server and local are in sync - ${syncRequest._id}');
        syncRequest.result!
          ..syncStatus = SyncStatus.success
          ..lastSyncedOn = DateTime.now().toUtc()
          ..dataChange = false;
        _syncComplete(syncRequest);
        _syncInProgress = false;
        return;
      }
    } on AtLookUpException catch (e) {
      _logger.severe(
          'Atlookup exception for sync ${syncRequest._id}. Reason ${e.toString()}');
      syncRequest.result!.atClientException =
          AtClientException(e.errorCode, e.errorMessage);
      _syncError(syncRequest);
      _syncInProgress = false;
      return;
    }
    _syncInProgress = true;
    final serverCommitId = await _getServerCommitId();
    await _sync(serverCommitId, syncRequest);
    _syncComplete(syncRequest);
    _syncInProgress = false;
  }

  /// Fetches the first app request from the queue. If there are no app requests, the first element of the
  /// queue is returned.
  SyncRequest _getSyncRequest() {
    return _syncRequests.firstWhere(
        (syncRequest) => syncRequest.requestSource == SyncRequestSource.app,
        orElse: () => _syncRequests.removeFirst());
  }

  void _syncError(SyncRequest syncRequest) {
    if (syncRequest.onError != null) {
      syncRequest.onError!(syncRequest.result);
    }
  }

  void _syncComplete(SyncRequest syncRequest) {
    syncRequest.result!.lastSyncedOn = DateTime.now().toUtc();
    // If specific onDone callback is set, call specific onDone callback,
    // else call the global onDone callback.
    if (syncRequest.onDone != null &&
        syncRequest.requestSource == SyncRequestSource.app) {
      syncRequest.onDone!(syncRequest.result);
    } else if (onDone != null) {
      onDone!(syncRequest.result);
    }
    _clearQueue();
  }

  void _onDone(SyncResult syncResult) {
    _logger.finer('system sync completed on ${syncResult.lastSyncedOn}');
  }

  void _onError(SyncResult syncResult) {
    _logger.severe(
        'system sync error ${syncResult.atClientException?.errorMessage}');
  }

  void _addSyncRequestToQueue(SyncRequest syncRequest) {
    if (_syncRequests.length == _queueSize) {
      _syncRequests.removeLast();
    }
    _syncRequests.addLast(syncRequest);
  }

  void _clearQueue() {
    _logger.finer('clearing sync queue');
    _syncRequests.clear();
  }

  Future<SyncResult> _sync(int serverCommitId, SyncRequest syncRequest) async {
    var syncResult = syncRequest.result!;
    try {
      _logger.finer('Sync in progress');
      var lastSyncedEntry = await SyncUtil.getLastSyncedEntry(
          _atClient.getPreferences()!.syncRegex,
          atSign: _atClient.getCurrentAtSign()!);
      // Get lastSyncedLocalSeq to get the list of uncommitted entries.
      var lastSyncedLocalSeq =
          lastSyncedEntry != null ? lastSyncedEntry.key : -1;
      var unCommittedEntries = await SyncUtil.getChangesSinceLastCommit(
          lastSyncedLocalSeq, _atClient.getPreferences()!.syncRegex,
          atSign: _atClient.getCurrentAtSign()!);
      var localCommitId = await _getLocalCommitId();
      if (serverCommitId > localCommitId) {
        _logger.finer('syncing to local');
        await _syncFromServer(serverCommitId, localCommitId);
      }
      if (unCommittedEntries.isNotEmpty) {
        _logger.finer(
            'syncing to remote. Total uncommitted entries: ${unCommittedEntries.length}');
        await _syncToRemote(unCommittedEntries);
      }
      syncResult.lastSyncedOn = DateTime.now().toUtc();
      syncResult.syncStatus = SyncStatus.success;
    } on Exception catch (e) {
      syncResult.atClientException =
          AtClientException(atClientErrorCodes['SyncException'], e.toString());
      syncResult.syncStatus = SyncStatus.failure;
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
    // Iterates until serverCommitId is greater than localCommitId are equal.
    while (serverCommitId > localCommitId) {
      var syncBuilder = SyncVerbBuilder()
        ..commitId = localCommitId
        ..regex = _atClient.getPreferences()!.syncRegex
        ..limit = _atClient.getPreferences()!.syncPageLimit
        ..isPaginated = true;
      _logger.finer('** syncBuilder ${syncBuilder.buildCommand()}');
      var syncResponse = DefaultResponseParser()
          .parse(await _remoteSecondary.executeVerb(syncBuilder));

      var syncResponseJson = JsonUtils.decodeJson(syncResponse.response);
      _logger.finest('** syncResponse $syncResponseJson');
      // Iterates over each commit
      await Future.forEach(syncResponseJson,
          (dynamic serverCommitEntry) => _syncLocal(serverCommitEntry));
      // assigning the lastSynced local commit id.
      localCommitId = await _getLocalCommitId();
      _logger.finest('**localCommitId $localCommitId');
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
    late String command;
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
  @override
  Future<bool> isInSync() async {
    if (_syncInProgress) {
      _logger.finest('*** isInSync..sync in progress');
      return true;
    }
    var serverCommitId = await _getServerCommitId();
    var lastSyncedEntry = await SyncUtil.getLastSyncedEntry(
        _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    var lastSyncedCommitId = lastSyncedEntry?.commitId;
    _logger.finest(
        'server commit id: $serverCommitId last synced commit id: $lastSyncedCommitId');
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
    var _serverCommitId = await SyncUtil.getLatestServerCommitId(
        _remoteSecondary, _atClient.getPreferences()!.syncRegex);
    // If server commit id is null, set to -1;
    _serverCommitId ??= -1;
    _logger.info('Returning the serverCommitId $_serverCommitId');
    return _serverCommitId;
  }

  /// Returns the local commit id. If null, returns -1.
  Future<int> _getLocalCommitId() async {
    // Get lastSynced local commit id.
    var lastSyncEntry = await SyncUtil.getLastSyncedEntry(
        _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    int localCommitId;
    // If lastSyncEntry not null, set localCommitId to lastSyncedEntry.commitId
    // Else set to -1.
    (lastSyncEntry != null && lastSyncEntry.commitId != null)
        ? localCommitId = lastSyncEntry.commitId!
        : localCommitId = -1;
    return localCommitId;
  }

  dynamic _sendBatch(List<BatchRequest> requests) async {
    var command = 'batch:';
    command += jsonEncode(requests);
    command += '\n';
    var verbResult = await _remoteSecondary.executeCommand(command, auth: true);
    _logger.finer('batch result:$verbResult');
    if (verbResult!.isNotEmpty) {
      verbResult = verbResult.replaceFirst('data:', '');
    }
    return jsonDecode(verbResult);
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
        _logger.finest(
            'syncing to local: ${serverCommitEntry['atKey']}  commitId:${serverCommitEntry['commitId']}');
        await _pullToLocal(builder, serverCommitEntry, CommitOp.UPDATE_ALL);
        break;
      case '-':
        var builder = DeleteVerbBuilder()..atKey = serverCommitEntry['atKey'];
        _logger.finest(
            'syncing to local delete: ${serverCommitEntry['atKey']}  commitId:${serverCommitEntry['commitId']}');
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
      builder.atKey.metadata = Metadata();
      if (metaData[AT_TTL] != null) {
        builder.atKey.metadata.ttl = int.parse(metaData[AT_TTL]);
      }
      if (metaData[AT_TTB] != null) {
        builder.atKey.metadata.ttb = int.parse(metaData[AT_TTB]);
      }
      if (metaData[AT_TTR] != null) {
        builder.atKey.metadata.ttr = int.parse(metaData[AT_TTR]);
      }
      if (metaData[CCD] != null) {
        (metaData[CCD].toLowerCase() == 'true')
            ? builder.atKey.metadata.ccd = true
            : builder.atKey.metadata.ccd = false;
      }
      if (metaData[PUBLIC_DATA_SIGNATURE] != null) {
        builder.atKey.metadata.dataSignature = metaData[PUBLIC_DATA_SIGNATURE];
      }
      if (metaData[IS_BINARY] != null) {
        (metaData[IS_BINARY].toLowerCase() == 'true')
            ? builder.atKey.metadata.isBinary = true
            : builder.atKey.metadata.isBinary = false;
      }
      if (metaData[IS_ENCRYPTED] != null) {
        (metaData[IS_ENCRYPTED].toLowerCase() == 'true')
            ? builder.atKey.metadata.isEncrypted = true
            : builder.atKey.metadata.isEncrypted = false;
      }
    }
  }

  Future<void> _pullToLocal(
      VerbBuilder builder, serverCommitEntry, CommitOp operation) async {
    var verbResult =
        await _atClient.getLocalSecondary()!.executeVerb(builder, sync: false);
    if (verbResult!.isEmpty) {
      return;
    }
    var sequenceNumber = int.parse(verbResult.split(':')[1]);
    var commitEntry = await (SyncUtil.getCommitEntry(
        sequenceNumber, _atClient.getCurrentAtSign()!));
    if (commitEntry == null) {
      return;
    }
    commitEntry.operation = operation;
    _logger.finest(
        '*** updating commitId to local ${serverCommitEntry['commitId']}');
    await SyncUtil.updateCommitEntry(commitEntry, serverCommitEntry['commitId'],
        _atClient.getCurrentAtSign()!);
  }

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    if (switchAtSignEvent.previousAtClient?.getCurrentAtSign() ==
        _atClient.getCurrentAtSign()) {
      // actions for previous atSign
      _syncRequests.clear();
      _logger.finer(
          'stopping stats notificationlistener for ${_atClient.getCurrentAtSign()}');
      _statsNotificationListener.stopAllSubscriptions();
      _cron.close();
      _syncServiceMap.remove(_atClient.getCurrentAtSign());
    }
  }

  @override
  void setOnDone(Function onDone) {
    this.onDone = onDone;
  }
}

///Class to represent sync response.
class SyncResult {
  SyncStatus syncStatus = SyncStatus.notStarted;
  AtClientException? atClientException;
  DateTime? lastSyncedOn;
  bool dataChange = true;

  @override
  String toString() {
    return 'Sync status: $syncStatus lastSyncedOn: $lastSyncedOn Exception: $atClientException';
  }
}

///Enum to represent the sync status
enum SyncStatus { notStarted, success, failure }

enum SyncRequestSource { app, system }

class SyncRequest {
  late String _id;
  SyncRequestSource requestSource = SyncRequestSource.app;
  late DateTime requestedOn;
  Function? onDone;
  Function? onError;
  SyncResult? result;

  SyncRequest({this.onDone, this.onError}) {
    _id = Uuid().v4();
    requestedOn = DateTime.now().toUtc();
  }
}
