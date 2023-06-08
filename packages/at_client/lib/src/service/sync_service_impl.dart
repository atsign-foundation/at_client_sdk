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
import 'package:at_client/src/util/logger_util.dart';
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
  static int syncRequestThreshold = 3,
      syncRequestTriggerInSeconds = 3,
      syncRunIntervalSeconds = 5,
      queueSize = 5;
  late final AtClient _atClient;
  late final RemoteSecondary _remoteSecondary;
  late final NotificationServiceImpl _statsNotificationListener;
  @visibleForTesting
  late AtKeyDecryptionManager atKeyDecryptionManager;

  /// utility method to reduce code verbosity in this file
  /// Does nothing if a telemetryService has not been injected
  void _sendTelemetry(String name, dynamic value) {
    _atClient.telemetry?.controller.sink.add(SyncTelemetryEvent(name, value));
  }

  @visibleForTesting
  SyncUtil syncUtil = SyncUtil();

  final List<SyncProgressListener> _syncProgressListeners = [];
  late final Cron _cron;
  final _syncRequests = ListQueue<SyncRequest>(queueSize);
  bool _syncInProgress = false;

  @override
  bool get isSyncInProgress => _syncInProgress;

  Function? onDone;

  late final AtSignLogger _logger;

  late AtClientManager _atClientManager;

  @visibleForTesting
  NetworkUtil networkUtil = NetworkUtil();

  /// Returns the currentAtSign associated with the SyncService
  String get currentAtSign => _atClient.getCurrentAtSign()!;

  /// A local AtKey to persist the last received server commitId
  late final AtKey _lastReceivedServerCommitIdAtKey;

  static Future<SyncService> create(AtClient atClient,
      {required AtClientManager atClientManager,
      required NotificationService notificationService,
      RemoteSecondary? remoteSecondary}) async {
    remoteSecondary ??= RemoteSecondary(
        atClient.getCurrentAtSign()!, atClient.getPreferences()!,
        atChops: atClient.atChops);
    final syncService = SyncServiceImpl._(
        atClientManager, atClient, notificationService, remoteSecondary);
    await syncService._statsServiceListener();
    syncService._scheduleSyncRun();
    return syncService;
  }

  SyncServiceImpl._(
      AtClientManager atClientManager,
      AtClient atClient,
      NotificationService notificationService,
      RemoteSecondary remoteSecondary) {
    _atClientManager = atClientManager;
    _atClient = atClient;
    _logger = AtSignLogger('SyncService (${_atClient.getCurrentAtSign()})');
    _remoteSecondary = remoteSecondary;
    _statsNotificationListener = notificationService as NotificationServiceImpl;
    _lastReceivedServerCommitIdAtKey =
        AtKey.local('lastreceivedservercommitid', currentAtSign).build();
    atKeyDecryptionManager = AtKeyDecryptionManager(_atClient);
    _atClientManager.listenToAtSignChange(this);
  }

  void _scheduleSyncRun() {
    _cron = Cron();

    _cron.schedule(Schedule.parse('*/$syncRunIntervalSeconds * * * * *'),
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
  void sync(
      {@Deprecated('Use SyncProgressListener') Function? onDone,
      Function? onError}) {
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
      _logger.finer(_logger.getLogMessageWithClientParticulars(
          _atClient.getPreferences()!.atClientParticulars,
          'RCVD: stats notification in sync: ${notification.value}'));
      final serverCommitId = notification.value;
      int localCommitId = -1;
      try {
        localCommitId = await _getLocalCommitId();
      } on FormatException catch (e) {
        _logger.finer('Exception occurred in statsListener ${e.message}');

        _statsNotificationListener.stopAllSubscriptions();
        var syncRequest = SyncRequest()
          ..result = (SyncResult()
            ..atClientException = AtClientException.message(e.message));
        _syncError(syncRequest);

        SyncProgress syncProgress = SyncProgress()
          ..atClientException = AtClientException.message(e.message)
          ..syncStatus = SyncStatus.failure;
        _informSyncProgress(syncProgress);
      }
      if (serverCommitId != null && int.parse(serverCommitId) > localCommitId) {
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
          (_syncRequests.length < syncRequestThreshold &&
              (_syncRequests.isNotEmpty &&
                  DateTime.now()
                          .toUtc()
                          .difference(_syncRequests.elementAt(0).requestedOn)
                          .inSeconds <
                      syncRequestTriggerInSeconds))) {
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
    if (localCommitIdBeforeSync == -1) {
      syncProgress.isInitialSync = true;
    }
    syncProgress.completedAt = DateTime.now().toUtc();
    syncProgress.atSign = _atClient.getCurrentAtSign();
    syncProgress.localCommitIdBeforeSync = localCommitIdBeforeSync;
    syncProgress.localCommitId = localCommitId;
    syncProgress.serverCommitId = serverCommitId;
    _logger.finer(
        "Informing ${_syncProgressListeners.length} listeners of $syncProgress");
    for (var listener in _syncProgressListeners) {
      try {
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
    _logger.info(_logger.getLogMessageWithClientParticulars(
        _atClient.getPreferences()!.atClientParticulars,
        'Inside syncComplete. syncRequest.requestSource : ${syncRequest.requestSource}; syncRequest.onDone : ${syncRequest.onDone}'));
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
    if (_syncRequests.length == queueSize) {
      _syncRequests.removeLast();
    }
    _syncRequests.addLast(syncRequest);
  }

  void _clearQueue() {
    _logger.finer(_logger.getLogMessageWithClientParticulars(
        _atClient.getPreferences()!.atClientParticulars,
        'Clearing sync queue'));
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
    var lastReceivedServerCommitId = await getLastReceivedServerCommitId();
    if (serverCommitId > lastReceivedServerCommitId) {
      _logger.finer(_logger.getLogMessageWithClientParticulars(
          _atClient.getPreferences()!.atClientParticulars,
          'Pulling changes into local secondary | lastReceivedServerCommitId $lastReceivedServerCommitId | serverCommitId $serverCommitId'));
      // Hint to casual reader: This is where we sync new changes from the server to this client
      final keyInfoList = await _syncFromServer(
          serverCommitId, lastReceivedServerCommitId, unCommittedEntries);
      syncResult.keyInfoList.addAll(keyInfoList);
    }
    if (unCommittedEntries.isNotEmpty) {
      _logger.finer(_logger.getLogMessageWithClientParticulars(
          _atClient.getPreferences()!.atClientParticulars,
          'Found uncommitted entries to sync to remote. Total uncommitted entries: ${unCommittedEntries.length}'));
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

            keyInfoList.add(KeyInfo(commitEntry.atKey,
                SyncDirection.localToRemote, commitEntry.operation));
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
  Future<List<KeyInfo>> _syncFromServer(
      int serverCommitId,
      int lastReceivedServerCommitId,
      List<CommitEntry> uncommittedEntries) async {
    // Iterates until serverCommitId is greater than lastReceivedServerCommitId.
    // replacing localCommitId with lastReceivedServerCommitId fixes infinite loop issue
    // in certain scenarios e.g server has a commit entry that need not be synced on client side,
    // server has delete commit entry and the key is not present on local keystore
    List<KeyInfo> keyInfoList = [];
    try {
      while (serverCommitId > lastReceivedServerCommitId) {
        _sendTelemetry('_syncFromServer.whileLoop', {
          "serverCommitId": serverCommitId,
          "lastReceivedServerCommitId": lastReceivedServerCommitId
        });
        List<dynamic> listOfCommitEntriesFromServer =
            await _getEntriesToSyncFromServer(lastReceivedServerCommitId);
        if (listOfCommitEntriesFromServer.isEmpty) {
          _logger.finer(_logger.getLogMessageWithClientParticulars(
              _atClient.getPreferences()!.atClientParticulars,
              'sync response is empty | local commitID: $lastReceivedServerCommitId | server commitID: $serverCommitId'));
          break;
        }
        // Iterates over each commit entry
        // If the serverCommitEntry exists in the uncommitted entries list,
        // ignore the serverCommitEntry.
        for (dynamic serverCommitEntry in listOfCommitEntriesFromServer) {
          bool isServerCommitEntryExistInUncommittedEntries = false;
          for (CommitEntry entry in uncommittedEntries) {
            if (entry.atKey!.trim() ==
                serverCommitEntry['atKey'].toString().trim()) {
              isServerCommitEntryExistInUncommittedEntries = true;
              break;
            }
          }
          if (isServerCommitEntryExistInUncommittedEntries) {
            lastReceivedServerCommitId =
                _parseToInteger(serverCommitEntry['commitId']);
            _logger.finer(_logger.getLogMessageWithClientParticulars(
                _atClient.getPreferences()!.atClientParticulars,
                'Server commitEntry ${serverCommitEntry['atKey']} exists in '
                'uncommitted entries. So skipping the commit entry and '
                'updating the lastReceivedServerCommitId to $lastReceivedServerCommitId'));
            ConflictInfo? conflictInfo =
                await _setConflictInfo(serverCommitEntry);
            final keyInfo = KeyInfo(
                serverCommitEntry['atKey'],
                SyncDirection.remoteToLocal,
                convertCommitOpSymbolToEnum(serverCommitEntry['operation']));
            keyInfo.conflictInfo = conflictInfo;
            keyInfoList.add(keyInfo);
            continue;
          }

          _sendTelemetry('_syncFromServer.forEachEntry.start', {
            "atKey": serverCommitEntry['atKey'],
            "operation": serverCommitEntry['operation'],
            "commitId": serverCommitEntry['commitId'],
          });
          // Convert the commit-id to "int" if in "String" data type.
          lastReceivedServerCommitId =
              _parseToInteger(serverCommitEntry['commitId']);
          await _processServerCommitEntry(
              serverCommitEntry, uncommittedEntries, keyInfoList);
          _logger.finest(
              '**lastReceivedServerCommitId $lastReceivedServerCommitId');
        }
      }
    } finally {
      // The put method persists the lastReceivedServerCommitId which will be used to
      // fetch the next set of entries to sync from server
      // Adding this piece in finally block to ensure lastReceivedServerCommitId state
      // is persisted even if there occurs any exception during sync to local.
      await _atClient.put(_lastReceivedServerCommitIdAtKey,
          lastReceivedServerCommitId.toString());
    }
    return keyInfoList;
  }

  Future<void> _processServerCommitEntry(serverCommitEntry,
      List<CommitEntry> uncommittedEntries, List<KeyInfo> keyInfoList) async {
    try {
      final keyInfo = KeyInfo(
          serverCommitEntry['atKey'],
          SyncDirection.remoteToLocal,
          convertCommitOpSymbolToEnum(serverCommitEntry['operation']));
      await _syncLocal(serverCommitEntry);
      keyInfoList.add(keyInfo);
      _sendTelemetry('_syncFromServer.forEachEntry.end', {
        'atKey': keyInfo.key,
        'syncDirection': keyInfo.syncDirection,
        'errorOrExceptionMessage': keyInfo.conflictInfo?.errorOrExceptionMessage
      });
    } on Exception catch (e, stacktrace) {
      _sendTelemetry(
          '_syncFromServer.forEachEntry.exception', {"e": e, "st": stacktrace});
      _logger.severe(
          'exception syncing entry to local $serverCommitEntry Exception: ${e.toString()} - stacktrace: $stacktrace');
    } on Error catch (e, stacktrace) {
      _sendTelemetry(
          '_syncFromServer.forEachEntry.error', {"e": e, "st": stacktrace});
      _logger.severe(
          'error syncing entry to local $serverCommitEntry - Exception: ${e.toString()} - stacktrace: $stacktrace');
    }
  }

  /// Takes the last received server commit id and fetches the entries that are above the given
  /// commit-id to sync into the local keystore.
  Future<List<dynamic>> _getEntriesToSyncFromServer(
      int lastReceivedServerCommitId) async {
    var syncBuilder = SyncVerbBuilder()
      ..commitId = lastReceivedServerCommitId
      ..regex = _atClient.getPreferences()!.syncRegex
      ..limit = _atClient.getPreferences()!.syncPageLimit
      ..isPaginated = true;
    _logger.finer(_logger.getLogMessageWithClientParticulars(
        _atClient.getPreferences()!.atClientParticulars,
        'syncBuilder ${syncBuilder.buildCommand()}'));
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
    _logger.finest(_logger.getLogMessageWithClientParticulars(
        _atClient.getPreferences()!.atClientParticulars,
        'syncResponse $syncResponseJson'));
    return syncResponseJson;
  }

  Future<ConflictInfo?> _setConflictInfo(final serverCommitEntry) async {
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
    if (atKey.sharedBy != null) {
      atKey.sharedBy = AtUtils.fixAtSign(atKey.sharedBy!);
    }
    final conflictInfo = ConflictInfo();
    try {
      final localAtValue = await _atClient.get(atKey);
      if (atKey is PublicKey || key.contains('public:')) {
        final serverValue = serverCommitEntry['value'];
        if (localAtValue.value != serverValue) {
          conflictInfo.localValue = localAtValue.value;
          conflictInfo.remoteValue = serverValue;
        }
        return conflictInfo;
      }
      final serverEncryptedValue = serverCommitEntry['value'];
      final serverMetaData = serverCommitEntry['metadata'];
      if (serverMetaData != null && serverMetaData[IS_ENCRYPTED] == "true") {
        final atKeyDecryption =
            atKeyDecryptionManager.get(atKey, _atClient.getCurrentAtSign()!);
        // ignore: prefer_typing_uninitialized_variables
        var serverDecryptedValue;
        if (serverEncryptedValue != null && serverEncryptedValue.isNotEmpty) {
          serverDecryptedValue =
              await atKeyDecryption.decrypt(atKey, serverEncryptedValue);
        }
        if (localAtValue.value != serverDecryptedValue) {
          conflictInfo.localValue = localAtValue.value;
          conflictInfo.remoteValue = serverDecryptedValue;
        }
      }
      return conflictInfo;
    } catch (e, st) {
      conflictInfo.errorOrExceptionMessage =
          'Exception occurred when setting conflict info for $atKey | $e';
      _logger.warning(conflictInfo.errorOrExceptionMessage, e, st);
      return conflictInfo;
    }
  }

  @visibleForTesting
  Future<List<BatchRequest>> getBatchRequests(
      List<CommitEntry> uncommittedEntries) async {
    var batchRequests = <BatchRequest>[];
    var batchId = 1;
    List<CommitEntry> removeUncommittedEntriesList = [];
    for (var entry in uncommittedEntries) {
      String command;
      // The update on a cached key is prevented. The logic in "validatePutRequest"
      // throws exception if a user tries to update a cached key.
      // The below check is for the older data. The cached keys that are updated
      // before the "validatePutRequest" is in-place.
      // However if they want to delete a cached key, they should be allowed to
      if (entry.atKey!.startsWith('cached:') &&
          entry.operation != CommitOp.DELETE) {
        _logger.finer(
            '${entry.atKey} is skipped. cached keys will not be synced to cloud secondary');
        removeUncommittedEntriesList.add(entry);
        continue;
      }
      // For CommitOp.Update, _getCommand fetches the data from the local keystore to sync to the server.
      // When getCommand is called for an entry where key is created/updated and then deleted,
      // a KeyNotFoundException will be thrown because the data does not exist in the keystore.
      try {
        command = await _getCommand(entry);
      } on KeyNotFoundException {
        _logger.severe(
            '${entry.atKey} is not found in keystore. Skipping to entry to sync');
        removeUncommittedEntriesList.add(entry);
        continue;
      }
      command = VerbUtil.replaceNewline(command);
      var batchRequest = BatchRequest(batchId, command);
      _logger.finer('batchId:$batchId key:${entry.atKey}');
      batchRequests.add(batchRequest);
      batchId++;
    }
    // The commit-id's in the batch response are updated to the appropriate commit-entry
    // in the uncommitted entries by iterating the uncommitted entries list.
    // If an entry is skipped in the batch request, then size of batch response
    // will be less than the size of uncommitted entries and so the commit-id gets
    // updated against the wrong uncommitted entry.
    // So, remove the commit entry from the uncommitted entries list.
    for (CommitEntry commitEntry in removeUncommittedEntriesList) {
      uncommittedEntries.remove(commitEntry);
      // Removing the entry from the commit log keystore to prevent stale entries
      await syncUtil.removeCommitEntry(commitEntry.key, currentAtSign);
    }
    removeUncommittedEntriesList.clear();
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

  String _metadataToString(AtMetaData? metadata) {
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

    if (metadata.sharedKeyEnc != null) {
      metadataStr += ':sharedKeyEnc:${metadata.sharedKeyEnc}';
    }
    if (metadata.pubKeyCS != null) {
      metadataStr += ':pubKeyCS:${metadata.pubKeyCS}';
    }
    if (metadata.encoding != null) {
      metadataStr += ':encoding:${metadata.encoding}';
    }
    if (metadata.encKeyName != null) {
      metadataStr += ':encKeyName:${metadata.encKeyName}';
    }
    if (metadata.encAlgo != null) {
      metadataStr += ':encAlgo:${metadata.encAlgo}';
    }
    if (metadata.ivNonce != null) {
      metadataStr += ':ivNonce:${metadata.ivNonce}';
    }
    if (metadata.skeEncKeyName != null) {
      metadataStr += ':skeEncKeyName:${metadata.skeEncKeyName}';
    }
    if (metadata.skeEncAlgo != null) {
      metadataStr += ':skeEncAlgo:${metadata.skeEncAlgo}';
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
          _atClient.getCurrentAtSign()!, _atClient.getPreferences()!,
          atChops: _atClient.atChops);
      var serverCommitId =
          await _getServerCommitId(remoteSecondary: remoteSecondary);

      var lastReceivedServerCommitId = await getLastReceivedServerCommitId();

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
          unCommittedEntries, serverCommitId, lastReceivedServerCommitId);
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
    var lastReceivedServerCommitId = await getLastReceivedServerCommitId();
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
        unCommittedEntries, serverCommitId, lastReceivedServerCommitId);
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
    _logger.info(_logger.getLogMessageWithClientParticulars(
        _atClient.getPreferences()!.atClientParticulars,
        'Returning serverCommitId $_serverCommitId'));
    return _serverCommitId;
  }

  @visibleForTesting
  Future<int> getLastReceivedServerCommitId() async {
    // If "lastReceivedServerCommitId" key exists, fetch the data and return the
    // last received server commit id.
    try {
      var response = await _atClient.get(_lastReceivedServerCommitIdAtKey);
      _logger.finer(_logger.getLogMessageWithClientParticulars(
          _atClient.getPreferences()!.atClientParticulars,
          'Returning lastReceivedServerCommitId from AtKey: ${response.value}'));
      return int.parse(response.value);
    } on AtKeyNotFoundException {
      // If the key does not exist, fall back to previous logic, which is
      // return last synced commit id.
      int localCommitId = await _getLocalCommitId();
      _logger.finer(_logger.getLogMessageWithClientParticulars(
          _atClient.getPreferences()!.atClientParticulars,
          'lastReceivedServerCommitId AtKey not found. Returning localCommitId: $localCommitId'));
      return localCommitId;
    }
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
    _logger.finer(_logger.getLogMessageWithClientParticulars(
        _atClient.getPreferences()!.atClientParticulars,
        'Sending batch to sync: $command'));
    var verbResult = await _remoteSecondary.executeCommand(command, auth: true);
    _logger.finer(_logger.getLogMessageWithClientParticulars(
        _atClient.getPreferences()!.atClientParticulars,
        'batch result:$verbResult'));
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
        var builder = DeleteVerbBuilder()
          ..atKeyObj = AtKey.fromString(serverCommitEntry['atKey']);
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

  void _setMetaData(UpdateVerbBuilder builder, serverCommitEntry) {
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
      if (metaData[ENCRYPTING_KEY_NAME] != null) {
        builder.encKeyName = metaData[ENCRYPTING_KEY_NAME];
      }
      if (metaData[ENCRYPTING_ALGO] != null) {
        builder.encAlgo = metaData[ENCRYPTING_ALGO];
      }
      if (metaData[IV_OR_NONCE] != null) {
        builder.ivNonce = metaData[IV_OR_NONCE];
      }
      if (metaData[SHARED_KEY_ENCRYPTED_ENCRYPTING_KEY_NAME] != null) {
        builder.skeEncKeyName =
            metaData[SHARED_KEY_ENCRYPTED_ENCRYPTING_KEY_NAME];
      }
      if (metaData[SHARED_KEY_ENCRYPTED_ENCRYPTING_ALGO] != null) {
        builder.skeEncAlgo = metaData[SHARED_KEY_ENCRYPTED_ENCRYPTING_ALGO];
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
    _atClientManager.removeChangeListeners(this);

    _syncRequests.clear();

    _logger.finer(
        'stopping stats notification listener for ${_atClient.getCurrentAtSign()}');
    _statsNotificationListener.stopAllSubscriptions();

    _logger.finer('stopping cron');
    _cron.close();

    removeAllProgressListeners();
  }

  @override
  void setOnDone(Function onDone) {
    this.onDone = onDone;
  }

  @visibleForTesting
  int syncProgressListenerSize() {
    return _syncProgressListeners.length;
  }

  @override
  void removeAllProgressListeners() {
    _syncProgressListeners.clear();
  }

  ///Method only for testing
  ///Clears all in-memory entities belonging to the syncService
  @visibleForTesting
  void clearSyncEntities() {
    _syncRequests.clear();
    _syncProgressListeners.clear();
  }

  int _parseToInteger(dynamic arg1) {
    if (arg1 is String) {
      return int.parse(arg1);
    }
    return arg1;
  }
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
