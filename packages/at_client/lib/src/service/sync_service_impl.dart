import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync/sync_request.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';
import 'package:cron/cron.dart';
import 'package:meta/meta.dart';

///A [SyncService] object is used to ensure data in local secondary(e.g mobile device) and cloud secondary are in sync.
class SyncServiceImpl implements SyncService, AtSignChangeListener {
  static const _syncRequestThreshold = 3,
      _syncRequestTriggerInSeconds = 3,
      _syncRunIntervalSeconds = 5,
      _queueSize = 5;
  late final AtClient _atClient;
  late final RemoteSecondary _remoteSecondary;
  late final NotificationServiceImpl _statsNotificationListener;

  /// utility method to reduce code verbosity in this file
  /// Does nothing if a telemetryService has not been injected
  void _sendTelemetry(String name, dynamic value) {
    _atClient.telemetry?.controller.sink.add(SyncTelemetryEvent(name, value));
  }

  @visibleForTesting
  SyncUtil syncUtil = SyncUtil();

  /// static because once listeners are added, they should be agnostic to switch atsign event
  static final Set<SyncProgressListener> _syncProgressListeners = HashSet();
  late final Cron _cron;
  final _syncRequests = ListQueue<SyncRequest>(_queueSize);
  static final Map<String, SyncService> _syncServiceMap = {};
  bool _syncInProgress = false;

  @override
  bool get isSyncInProgress => _syncInProgress;

  Function? onDone;

  final _logger = AtSignLogger('SyncService');

  late AtClientManager _atClientManager;

  @visibleForTesting
  NetworkUtil networkUtil = NetworkUtil();

  /// Returns the currentAtSign associated with the SyncService
  String get currentAtSign => _atClient.getCurrentAtSign()!;

  static Future<SyncService> create(AtClient atClient,
      {required AtClientManager atClientManager,
      required NotificationService notificationService,
      RemoteSecondary? remoteSecondary}) async {
    if (_syncServiceMap.containsKey(atClient.getCurrentAtSign())) {
      return _syncServiceMap[atClient.getCurrentAtSign()]!;
    }

    remoteSecondary ??= RemoteSecondary(
        atClient.getCurrentAtSign()!, atClient.getPreferences()!);
    final syncService = SyncServiceImpl._(
        atClientManager, atClient, notificationService, remoteSecondary);
    await syncService._statsServiceListener();
    syncService._scheduleSyncRun();
    _syncServiceMap[atClient.getCurrentAtSign()!] = syncService;
    return _syncServiceMap[atClient.getCurrentAtSign()]!;
  }

  SyncServiceImpl._(
      AtClientManager atClientManager,
      AtClient atClient,
      NotificationService notificationService,
      RemoteSecondary remoteSecondary) {
    _atClientManager = atClientManager;
    _atClient = atClient;
    _remoteSecondary = remoteSecondary;
    _statsNotificationListener = notificationService as NotificationServiceImpl;
    _atClientManager.listenToAtSignChange(this);
  }

  void _scheduleSyncRun() {
    _cron = Cron();

    _cron.schedule(Schedule.parse('*/$_syncRunIntervalSeconds * * * * *'),
        () async {
      try {
        await processSyncRequests();
        // If no sync request has ever been made, let's enqueue one now.
        // See https://github.com/atsign-foundation/at_client_sdk/issues/770
        if (hasHadNoSyncRequests) {
          final syncRequest = SyncRequest();
          syncRequest.onDone = _onDone;
          syncRequest.onError = _onError;
          syncRequest.requestSource = SyncRequestSource.system;
          syncRequest.requestedOn = DateTime.now().toUtc();
          syncRequest.result = SyncResult();
          _addSyncRequestToQueue(syncRequest);
        }
      } on Exception catch (e, trace) {
        var cause = (e is AtException) ? e.getTraceMessage() : e.toString();
        _logger.finest(trace);
        _logger.severe('exception while running process sync. Reason:  $cause');
        _syncInProgress = false;
      }
    });
  }

  @override
  void sync({Function? onDone, Function? onError}) {
    final syncRequest = SyncRequest();
    syncRequest.onDone = onDone;
    syncRequest.onError = onError;
    syncRequest.requestSource = SyncRequestSource.app;
    syncRequest.requestedOn = DateTime.now().toUtc();
    syncRequest.result = SyncResult();
    _addSyncRequestToQueue(syncRequest);
    return;
  }

  /// Listens on stats notification sent by the cloud secondary server
  Future<void> _statsServiceListener() async {
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

  @override
  void addProgressListener(SyncProgressListener listener) {
    _syncProgressListeners.add(listener);
  }

  @override
  void removeProgressListener(SyncProgressListener listener) {
    _syncProgressListeners.remove(listener);
  }

  @visibleForTesting
  Future<void> processSyncRequests(
      {bool respectSyncRequestQueueSizeAndRequestTriggerDuration =
          true}) async {
    final syncProgress = SyncProgress()..syncStatus = SyncStatus.started;
    syncProgress.startedAt = DateTime.now().toUtc();
    _logger.finest('in _processSyncRequests');
    if (_syncInProgress) {
      _logger.finer('**** another sync in progress');
      syncProgress.message = 'another sync in progress';
      _informSyncProgress(syncProgress);
      return;
    }
    if (!await networkUtil.isNetworkAvailable()) {
      _logger.finer('skipping sync due to network unavailability');
      syncProgress.syncStatus = SyncStatus.failure;
      syncProgress.message = 'network unavailable';
      _informSyncProgress(syncProgress);
      return;
    }
    if (respectSyncRequestQueueSizeAndRequestTriggerDuration) {
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
    }
    final syncRequest = _getSyncRequest();
    try {
      if (await _isInSync()) {
        _logger.finer('server and local are in sync - ${syncRequest.id}');
        syncRequest.result!
          ..syncStatus = SyncStatus.success
          ..lastSyncedOn = DateTime.now().toUtc()
          ..dataChange = false;
        _syncComplete(syncRequest);
        _syncInProgress = false;
        syncProgress.syncStatus = SyncStatus.success;
        _informSyncProgress(syncProgress);
        return;
      }

      _syncInProgress = true;
      int serverCommitId = await _getServerCommitId();
      final localCommitIdBeforeSync = await _getLocalCommitId();

      // Hint for the casual reader - main sync algorithm is in [syncInternal]
      final syncResult = await syncInternal(serverCommitId, syncRequest);

      _syncComplete(syncRequest);
      syncProgress.syncStatus = syncResult.syncStatus;
      syncProgress.keyInfoList = syncResult.keyInfoList;
      serverCommitId = await _getServerCommitId();
      final localCommitId = await _getLocalCommitId();
      _informSyncProgress(syncProgress,
          localCommitIdBeforeSync: localCommitIdBeforeSync,
          localCommitId: localCommitId,
          serverCommitId: serverCommitId);
      _syncInProgress = false;
    } on AtException catch (e) {
      e.stack(AtChainedException(Intent.syncData,
          ExceptionScenario.remoteVerbExecutionFailed, e.message));
      _logger.severe(
          'Exception in sync ${syncRequest.id}. Reason: ${e.getTraceMessage()}');
      syncRequest.result!.atClientException =
          AtExceptionManager.createException(e);
      _syncError(syncRequest);
      _syncInProgress = false;
      syncProgress.syncStatus = SyncStatus.failure;
      _informSyncProgress(syncProgress);
    }
    return;
  }

  void _informSyncProgress(SyncProgress syncProgress,
      {int? localCommitIdBeforeSync, int? localCommitId, int? serverCommitId}) {
    for (var listener in _syncProgressListeners) {
      if (localCommitIdBeforeSync == -1) {
        syncProgress.isInitialSync = true;
      }
      try {
        syncProgress.completedAt = DateTime.now().toUtc();
        syncProgress.atSign = _atClient.getCurrentAtSign();
        syncProgress.localCommitIdBeforeSync = localCommitIdBeforeSync;
        syncProgress.localCommitId = localCommitId;
        syncProgress.serverCommitId = serverCommitId;
        listener.onSyncProgressEvent(syncProgress);
      } on Exception catch (e) {
        var cause = (e is AtException) ? e.getTraceMessage() : e.toString();
        _logger.severe(
            'unable to inform sync progress to listener $listener. Reason: $cause');
      }
    }
  }

  /// Fetches the first app request from the queue. If there are no app requests, the first element of the
  /// queue is returned.
  SyncRequest _getSyncRequest() {
    return _syncRequests.firstWhere(
        (syncRequest) =>
            syncRequest.requestSource == SyncRequestSource.app &&
            syncRequest.onDone != null,
        orElse: () => _syncRequests.removeFirst());
  }

  void _syncError(SyncRequest syncRequest) {
    if (syncRequest.onError != null) {
      syncRequest.onError!(syncRequest.result);
    }
  }

  void _syncComplete(SyncRequest syncRequest) {
    syncRequest.result!.lastSyncedOn = DateTime.now().toUtc();
    _logger.info(
        'Inside syncComplete. syncRequest.requestSource : ${syncRequest.requestSource} ; syncRequest.onDone : ${syncRequest.onDone}');
    // If specific onDone callback is set, call specific onDone callback,
    // else call the global onDone callback.
    if (syncRequest.onDone != null &&
        syncRequest.requestSource == SyncRequestSource.app) {
      _logger.info('Sending result to onDone callback');
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
    _logger
        .severe('system sync error ${syncResult.atClientException?.message}');
  }

  /// We use this so that after [processSyncRequests] runs, it can enqueue a sync
  /// request if none have yet been received. This is to address a side-effect
  /// of the fix for https://github.com/atsign-foundation/at_client_sdk/issues/770
  @visibleForTesting
  bool hasHadNoSyncRequests = true;

  void _addSyncRequestToQueue(SyncRequest syncRequest) {
    hasHadNoSyncRequests = false;
    if (_syncRequests.length == _queueSize) {
      _syncRequests.removeLast();
    }
    _syncRequests.addLast(syncRequest);
  }

  void _clearQueue() {
    _logger.finer('clearing sync queue');
    _syncRequests.clear();
  }

  @visibleForTesting
  Future<SyncResult> syncInternal(
      int serverCommitId, SyncRequest syncRequest) async {
    var syncResult = syncRequest.result!;
    _logger.finer('Sync in progress');
    var lastSyncedEntry = await syncUtil.getLastSyncedEntry(
        _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    // Get lastSyncedLocalSeq to get the list of uncommitted entries.
    var lastSyncedLocalSeq = lastSyncedEntry != null ? lastSyncedEntry.key : -1;
    var unCommittedEntries = await syncUtil.getChangesSinceLastCommit(
        lastSyncedLocalSeq, _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    var localCommitId = await _getLocalCommitId();
    if (serverCommitId > localCommitId) {
      _logger.finer(
          'syncing to local: localCommitId $localCommitId serverCommitId $serverCommitId');

      // Hint to casual reader: This is where we sync new changes from the server to this this client
      final keyInfoList = await _syncFromServer(
          serverCommitId, localCommitId, unCommittedEntries);

      syncResult.keyInfoList.addAll(keyInfoList);
    }
    if (unCommittedEntries.isNotEmpty) {
      _logger.finer(
          'syncing to remote. Total uncommitted entries: ${unCommittedEntries.length}');

      // Hint to casual reader: This is where we sync new changes from this client to the server
      final keyInfoList = await _syncToRemote(unCommittedEntries);

      syncResult.keyInfoList.addAll(keyInfoList);
    }
    syncResult.lastSyncedOn = DateTime.now().toUtc();
    syncResult.syncStatus = SyncStatus.success;

    return syncResult;
  }

  /// Syncs the local entries to cloud secondary.
  Future<List<KeyInfo>> _syncToRemote(
      List<CommitEntry> unCommittedEntries) async {
    List<KeyInfo> keyInfoList = [];
    var uncommittedEntryBatch = getUnCommittedEntryBatch(unCommittedEntries);
    for (var unCommittedEntryList in uncommittedEntryBatch) {
      try {
        var batchRequests = await getBatchRequests(unCommittedEntryList);
        var batchResponse = await sendBatch(batchRequests);
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
                  '${commitEntry.operation} for key ${commitEntry.atKey} failed. Error code ${responseObject.errorCode} error message ${responseObject.errorMessage}');
            }

            _logger.finer('***batchId:$batchId key: ${commitEntry.atKey}');
            await syncUtil.updateCommitEntry(
                commitEntry, commitId, _atClient.getCurrentAtSign()!);
            keyInfoList
                .add(KeyInfo(commitEntry.atKey, SyncDirection.localToRemote));
          } on Exception catch (e) {
            var cause = (e is AtException) ? e.getTraceMessage() : e.toString();
            _logger.severe(
                'exception while updating commit entry for entry:$entry Reason: $cause');
          }
        }
      } on Exception catch (e) {
        var cause = (e is AtException) ? e.getTraceMessage() : e.toString();
        _logger.severe(
            'exception occurred while syncing batch commit entries: $unCommittedEntryList  Reason: $cause');
      }
    }
    return keyInfoList;
  }

  /// Syncs the cloud secondary changes to local secondary.
  Future<List<KeyInfo>> _syncFromServer(int serverCommitId, int localCommitId,
      List<CommitEntry> uncommittedEntries) async {
    // Iterates until serverCommitId is greater than lastReceivedServerCommitId.
    // replacing localCommitId with lastReceivedServerCommitId fixes infinite loop issue
    // in certain scenarios e.g server has a commit entry that need not be synced on client side,
    // server has delete commit entry and the key is not present on local keystore
    List<KeyInfo> keyInfoList = [];
    int lastReceivedServerCommitId = localCommitId;
    while (serverCommitId > lastReceivedServerCommitId) {
      _sendTelemetry('_syncFromServer.whileLoop', {
        "serverCommitId": serverCommitId,
        "lastReceivedServerCommitId": lastReceivedServerCommitId
      });

      var syncBuilder = SyncVerbBuilder()
        ..commitId = localCommitId
        ..regex = _atClient.getPreferences()!.syncRegex
        ..limit = _atClient.getPreferences()!.syncPageLimit
        ..isPaginated = true;
      _logger.finer('** syncBuilder ${syncBuilder.buildCommand()}');
      List syncResponseJson = [];
      try {
        syncResponseJson = JsonUtils.decodeJson(DefaultResponseParser()
            .parse(await _remoteSecondary.executeVerb(syncBuilder))
            .response);
      } on AtException catch (e) {
        e.stack(AtChainedException(Intent.syncData,
            ExceptionScenario.remoteVerbExecutionFailed, e.message));
        _logger.severe(
            'Exception occurred in fetching sync response : ${e.getTraceMessage()}');
        rethrow;
      }
      _logger.finest('** syncResponse $syncResponseJson');

      if (syncResponseJson.isEmpty) {
        _logger.finer(
            'sync response is empty: local commitID: $localCommitId server commitID: $serverCommitId');
        break;
      }
      // Iterates over each commit
      for (dynamic serverCommitEntry in syncResponseJson) {
        _sendTelemetry('_syncFromServer.forEachEntry.start', {
          "atKey": serverCommitEntry['atKey'],
          "operation": serverCommitEntry['operation'],
          "commitId": serverCommitEntry['commitId'],
        });
        if (serverCommitEntry['commitId'] is int) {
          lastReceivedServerCommitId = serverCommitEntry['commitId'];
        } else {
          lastReceivedServerCommitId = int.parse(serverCommitEntry['commitId']);
        }
        try {
          final keyInfo =
              KeyInfo(serverCommitEntry['atKey'], SyncDirection.remoteToLocal);
          ConflictInfo? conflictInfo =
              await _checkConflict(serverCommitEntry, uncommittedEntries);
          keyInfo.conflictInfo = conflictInfo;
          await _syncLocal(serverCommitEntry);
          keyInfoList.add(keyInfo);
          _sendTelemetry('_syncFromServer.forEachEntry.end', {
            'atKey': keyInfo.key,
            'syncDirection': keyInfo.syncDirection,
            'errorOrExceptionMessage':
                keyInfo.conflictInfo?.errorOrExceptionMessage
          });
        } on Exception catch (e, stacktrace) {
          _sendTelemetry('_syncFromServer.forEachEntry.exception',
              {"e": e, "st": stacktrace});
          _logger.severe(
              'exception syncing entry to local $serverCommitEntry Exception: ${e.toString()} - stacktrace: $stacktrace');
        } on Error catch (e, stacktrace) {
          _sendTelemetry(
              '_syncFromServer.forEachEntry.error', {"e": e, "st": stacktrace});
          _logger.severe(
              'error syncing entry to local $serverCommitEntry - Exception: ${e.toString()} - stacktrace: $stacktrace');
        }
      }
      // assigning the lastSynced local commit id.
      localCommitId = await _getLocalCommitId();
      _logger
          .finest('**lastReceivedServerCommitId $lastReceivedServerCommitId');
    }
    return keyInfoList;
  }

  Future<ConflictInfo?> _checkConflict(
      final serverCommitEntry, List<CommitEntry> uncommittedEntries) async {
    final key = serverCommitEntry['atKey'];

    // publickey.<atsign>@<currentatsign> is used to store the public key of
    // other atsign. The value is not encrypted.
    // The keys starting with publickey. and shared_key. are the reserved keys
    // and do not require actions. Hence skipping from checking conflict resolution.
    if (key.startsWith('publickey.') ||
        key.startsWith('shared_key.') ||
        key.startsWith('cached:')) {
      _logger.finer('$key found in conflict resolution, returning null');
      return null;
    }
    final atKey = AtKey.fromString(key);
    // temporary fix to add @ to sharedBy. permanent fix should be in AtKey.fromString
    atKey.sharedBy = AtUtils.formatAtSign(atKey.sharedBy);

    bool serverCommitEntryKeyExistsInLocalUncommittedEntries = false;
    for (CommitEntry entry in uncommittedEntries) {
      if (key == entry.atKey) {
        serverCommitEntryKeyExistsInLocalUncommittedEntries = true;
      }
    }

    if (!serverCommitEntryKeyExistsInLocalUncommittedEntries) {
      return null;
    }

    final conflictInfo = ConflictInfo();

    try {
      final localValue =
          await _atClient.getLocalSecondary()!.keyStore!.get(key);
      if (atKey is PublicKey || key.contains('public:')) {
        final serverValue = serverCommitEntry['value'];
        if (localValue != serverValue) {
          conflictInfo.localValue = localValue;
          conflictInfo.remoteValue = serverValue;
        }
        return conflictInfo;
      }
      final serverEncryptedValue = serverCommitEntry['value'];
      final serverMetaData = serverCommitEntry['metadata'];
      if (serverMetaData != null && serverMetaData[IS_ENCRYPTED] == "true") {
        final decryptionManager = AtKeyDecryptionManager(_atClient)
            .get(atKey, _atClient.getCurrentAtSign()!);

        // ignore: prefer_typing_uninitialized_variables
        var serverDecryptedValue;

        if (serverEncryptedValue != null && serverEncryptedValue.isNotEmpty) {
          serverDecryptedValue =
              await decryptionManager.decrypt(atKey, serverEncryptedValue);
        }
        final localDecryptedValue = await _atClient.get(atKey);
        if (localDecryptedValue.value != serverDecryptedValue) {
          conflictInfo.localValue = localDecryptedValue.value;
          conflictInfo.remoteValue = serverDecryptedValue;
        }
      }
      return conflictInfo;
    } catch (e, st) {
      conflictInfo.errorOrExceptionMessage =
          '_checkConflict for $atKey encountered exception $e';
      _logger.warning(conflictInfo.errorOrExceptionMessage, e, st);
      return conflictInfo;
    }
  }

  @visibleForTesting
  Future<List<BatchRequest>> getBatchRequests(
      List<CommitEntry> uncommittedEntries) async {
    var batchRequests = <BatchRequest>[];
    var batchId = 1;
    for (var entry in uncommittedEntries) {
      String command;
      //Skipping the cached keys to sync to cloud secondary.
      if (entry.atKey!.startsWith('cached:')) {
        _logger.finer(
            '${entry.atKey} is skipped. cached keys will not be synced to cloud secondary');
        continue;
      }
      try {
        command = await _getCommand(entry);
      } on KeyNotFoundException {
        _logger.severe(
            '${entry.atKey} is not found in keystore. Skipping to entry to sync');
        continue;
      }
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
          key = '$key${_metadataToString(metaData)}';
        }
        command = 'update:meta:$key';
        break;
      case CommitOp.UPDATE_ALL:
        var key = entry.atKey;
        AtData value = await _atClient.getLocalSecondary()!.keyStore!.get(key);
        var keyGen = '';
        keyGen = _metadataToString(value.metaData);
        keyGen += ':$key';
        command = 'update$keyGen ${value.data}';
        break;
    }
    return command;
  }

  String _metadataToString(dynamic metadata) {
    if (metadata == null) {
      return '';
    }
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
    // The older key entries will not have metadata.sharedKeyEncrypted and metadata.pubKeyChecksum
    // Hence handling the NoSuchMethodError.
    try {
      if (metadata.sharedKeyEnc != null) {
        metadataStr += ':sharedKeyEnc:${metadata.sharedKeyEnc}';
      }
      if (metadata.pubKeyCS != null) {
        metadataStr += ':pubKeyCS:${metadata.pubKeyCS}';
      }
      if (metadata.encoding != null) {
        metadataStr += ':encoding:${metadata.encoding}';
      }
    } on NoSuchMethodError {
      // ignore for uncommitted entries added before shared key metadata version
      _logger.finest('The entry is created with the older metadata');
    }
    return metadataStr;
  }

  ///Verifies if local secondary are cloud secondary are in sync.
  ///Returns true if local secondary and cloud secondary are in sync; else false.
  ///Throws [AtClientException] if cloud secondary is not reachable
  @override
  Future<bool> isInSync() async {
    late RemoteSecondary remoteSecondary;
    try {
      remoteSecondary = RemoteSecondary(
          _atClient.getCurrentAtSign()!, _atClient.getPreferences()!);
      var serverCommitId =
          await _getServerCommitId(remoteSecondary: remoteSecondary);

      var lastSyncedEntry = await syncUtil.getLastSyncedEntry(
          _atClient.getPreferences()!.syncRegex,
          atSign: _atClient.getCurrentAtSign()!);
      var lastSyncedCommitId = lastSyncedEntry?.commitId;
      _logger.finest(
          'server commit id: $serverCommitId last synced commit id: $lastSyncedCommitId');
      var lastSyncedLocalSeq =
          lastSyncedEntry != null ? lastSyncedEntry.key : -1;
      var unCommittedEntries = await syncUtil.getChangesSinceLastCommit(
          lastSyncedLocalSeq, _atClient.getPreferences()!.syncRegex,
          atSign: _atClient.getCurrentAtSign()!);
      return SyncUtil.isInSync(
          unCommittedEntries, serverCommitId, lastSyncedCommitId);
    } on Exception catch (e) {
      var cause = (e is AtException) ? e.getTraceMessage() : e.toString();
      _logger.severe('exception in isInSync $cause');
      throw AtClientException.message(e.toString());
    } finally {
      unawaited(remoteSecondary.atLookUp.close());
    }
  }

  Future<bool> _isInSync() async {
    if (_syncInProgress) {
      _logger.finest('*** isInSync..sync in progress');
      return true;
    }
    var serverCommitId =
        await _getServerCommitId(remoteSecondary: _remoteSecondary);
    var lastSyncedEntry = await syncUtil.getLastSyncedEntry(
        _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    var lastSyncedCommitId = lastSyncedEntry?.commitId;
    _logger.finest(
        'server commit id: $serverCommitId last synced commit id: $lastSyncedCommitId');
    var lastSyncedLocalSeq = lastSyncedEntry != null ? lastSyncedEntry.key : -1;
    var unCommittedEntries = await syncUtil.getChangesSinceLastCommit(
        lastSyncedLocalSeq, _atClient.getPreferences()!.syncRegex,
        atSign: _atClient.getCurrentAtSign()!);
    return SyncUtil.isInSync(
        unCommittedEntries, serverCommitId, lastSyncedCommitId);
  }

  /// Returns the cloud secondary latest commit id. if null, returns -1.
  ///Throws [AtLookUpException] if secondary is not reachable
  Future<int> _getServerCommitId({RemoteSecondary? remoteSecondary}) async {
    remoteSecondary ??= _remoteSecondary;
    // ignore: no_leading_underscores_for_local_identifiers
    var _serverCommitId = await syncUtil.getLatestServerCommitId(
        remoteSecondary, _atClient.getPreferences()!.syncRegex);
    // If server commit id is null, set to -1;
    _serverCommitId ??= -1;
    _logger.info('Returning the serverCommitId $_serverCommitId');
    return _serverCommitId;
  }

  /// Returns the local commit id. If null, returns -1.
  Future<int> _getLocalCommitId() async {
    // Get lastSynced local commit id.
    var lastSyncEntry = await syncUtil.getLastSyncedEntry(
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

  @visibleForTesting
  dynamic sendBatch(List<BatchRequest> requests) async {
    var command = 'batch:';
    command += jsonEncode(requests);
    command += '\n';
    var verbResult = await _remoteSecondary.executeCommand(command, auth: true);
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
          ..atKeyObj = AtKey.fromString(serverCommitEntry['atKey'])
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

  @visibleForTesting
  List<dynamic> getUnCommittedEntryBatch(
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
      if (metaData[SHARED_KEY_ENCRYPTED] != null) {
        builder.sharedKeyEncrypted = metaData[SHARED_KEY_ENCRYPTED];
      }
      if (metaData[SHARED_WITH_PUBLIC_KEY_CHECK_SUM] != null) {
        builder.pubKeyChecksum = metaData[SHARED_WITH_PUBLIC_KEY_CHECK_SUM];
      }
      if (metaData[ENCODING] != null) {
        builder.encoding = metaData[ENCODING];
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
    var commitEntry = await (syncUtil.getCommitEntry(
        sequenceNumber, _atClient.getCurrentAtSign()!));
    if (commitEntry == null) {
      return;
    }
    commitEntry.operation = operation;
    _logger.finest(
        '*** updating commitId to local ${serverCommitEntry['commitId']}');
    await syncUtil.updateCommitEntry(commitEntry, serverCommitEntry['commitId'],
        _atClient.getCurrentAtSign()!);
  }

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    if (switchAtSignEvent.previousAtClient?.getCurrentAtSign() ==
        _atClient.getCurrentAtSign()) {
      // actions for previous atSign
      _syncRequests.clear();
      _logger.finer(
          'stopping stats notification listener for ${_atClient.getCurrentAtSign()}');
      _statsNotificationListener.stopAllSubscriptions();
      _cron.close();
      _logger.finer(
          'removing from _syncServiceMap: ${_atClient.getCurrentAtSign()}');
      _atClientManager.removeChangeListeners(
          (_syncServiceMap[_atClient.getCurrentAtSign()]) as SyncServiceImpl);
      _syncServiceMap.remove(_atClient.getCurrentAtSign());
    }
  }

  @override
  void setOnDone(Function onDone) {
    this.onDone = onDone;
  }

  @visibleForTesting
  int syncProgressListenerSize() {
    return _syncProgressListeners.length;
  }

  ///Method only for testing
  ///Clears all in-memory entities belonging to the syncService
  @visibleForTesting
  void clearSyncEntities() {
    _syncRequests.clear();
    _syncProgressListeners.clear();
    _syncServiceMap.clear();
  }
}

class KeyInfo {
  String key;
  SyncDirection syncDirection;
  ConflictInfo? conflictInfo;

  KeyInfo(this.key, this.syncDirection);

  @override
  String toString() {
    return 'KeyInfo{key: $key, syncDirection: $syncDirection , conflictInfo: $conflictInfo}';
  }
}

enum SyncDirection { localToRemote, remoteToLocal }
