import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    hide AtNotification;
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

///A [SyncService] object is used to ensure data in local secondary(e.g mobile device) and cloud secondary are in sync.
class SyncServiceImpl implements SyncService {
  /// Bound on the in-memory request queue. When the queue fills, the
  /// oldest entry is dropped on the next enqueue. Mutable static so
  /// test infrastructure can set it to 1 (one-at-a-time semantics)
  /// for deterministic per-call assertions.
  static int queueSize = 5;
  final AtClient _atClient;
  final RemoteSecondary _remoteSecondary;
  @visibleForTesting
  late AtKeyDecryptionManager atKeyDecryptionManager;
  StreamSubscription<AtNotification>? _statsNotificationSubscription;

  /// utility method to reduce code verbosity in this file
  /// Does nothing if a telemetryService has not been injected
  void _sendTelemetry(String name, dynamic value) {
    _atClient.telemetry?.controller.sink.add(SyncTelemetryEvent(name, value));
  }

  @visibleForTesting
  SyncUtil syncUtil = SyncUtil();

  final List<SyncProgressListener> _syncProgressListeners = [];

  @visibleForTesting
  final syncRequests = ListQueue<SyncRequest>(queueSize);

  bool _syncInProgress = false;

  /// Concurrency guard for [processSyncRequests] entry. Distinct from
  /// [_syncInProgress] because [_isInSync] short-circuits on the latter
  /// — using [_syncInProgress] as the entry guard would cause every
  /// run to take the in-sync fast path. Set true at the top of a run,
  /// cleared in the run's `finally`.
  bool _processInProgress = false;

  /// Cached latest known server commit id. Kept fresh by three
  /// authoritative sources:
  ///   * [statsServiceListener]: push-side stats notifications.
  ///   * [_syncToRemote]: each successful entry in the batch response
  ///     carries the server commit id assigned to that op.
  ///   * [_syncFromServer]: each pulled commit entry's `commitId`.
  /// Read by [_getServerCommitId], which falls back to a remote
  /// stats fetch only when this is `null` (cold start, before any
  /// of the above has populated it).
  ///
  /// Distinct from the `serverCommitId` parameters / locals used
  /// inside a single sync run, which are *snapshots* captured at
  /// the start of that run and held constant for its duration.
  /// This field is the live, monotonic high-water mark across the
  /// whole [SyncServiceImpl] lifetime.
  int? _latestKnownServerCommitId;

  /// Highest server commit id assigned to one of OUR local writes
  /// via a successful push response. Promoted only by
  /// [_pushFromSyncQueue]; advances on each per-entry success in
  /// the batch response. `null` until the first successful push.
  ///
  /// Pre-`decouple-sync-from-commit-log` this number was derived by
  /// scanning the local commit log for the highest entry whose
  /// `commitId` field was non-null — `_syncToRemote` wrote each
  /// server-assigned commitId back into its source `CommitEntry`
  /// for exactly that purpose. The new push path doesn't touch
  /// commit-log entries (they're not the source of truth for sync
  /// any more), so we track the same high-water mark in this
  /// field directly. [_getLocalCommitId] reads from here.
  int? _highestPushedCommitId;

  /// Wall-clock time at which the last [processSyncRequests] run
  /// finished (whether it found work or took the in-sync fast path).
  /// Read by the periodic safety-net timer to decide whether enough
  /// time has elapsed to fire a defensive sync. `null` until the first
  /// run completes.
  @visibleForTesting
  DateTime? lastSyncCompletedAt;

  /// Periodic safety-net timer — fires every [_periodicSyncInterval]
  /// and, if the last completed sync run is older than that interval,
  /// calls [sync] to drive a fresh run. Production triggers (app
  /// `sync()` calls, stats notifications, post-run drains) are still
  /// the hot path; this timer just guards against the case where any
  /// of those silently fail (a dropped notification, an unhandled
  /// exception path, etc.). Cancelled in [stop], restarted in
  /// [start].
  Timer? _periodicSyncTimer;
  static const Duration _periodicSyncInterval = Duration(seconds: 30);

  @override
  bool get isSyncInProgress => _syncInProgress;

  Function? onDone;

  late final AtSignLogger _logger;

  // "^shared_key\..+@.+" matches the key that starts-with shared_key.<someone>@<me>
  // "@.+:shared_key@.+" matches the key that starts-with @<someone>:shared_key@<me>
  @visibleForTesting
  RegExp encryptedSharedKeyMatcher =
      RegExp(r'^shared_key\..+@.+|@.+:shared_key@.+');

  /// Returns the currentAtSign associated with the SyncService
  String get currentAtSign => _atClient.getCurrentAtSign()!;

  /// A local AtKey to persist the last received server commitId
  late final AtKey _lastReceivedServerCommitIdAtKey;

  /// A local AtKey to store skipDeletesUntil value
  late final AtKey _skipDeletesUntilCommitId;

  static Future<SyncService> create(AtClient atClient,
      {@Deprecated('will be removed in a future version')
      AtClientManager? atClientManager,
      RemoteSecondary? remoteSecondary}) async {
    remoteSecondary ??= RemoteSecondary(
        atClient.getCurrentAtSign()!, atClient.getPreferences()!,
        atChops: atClient.atChops, enrollmentId: atClient.enrollmentId);
    final syncService = SyncServiceImpl._(atClient, remoteSecondary);
    await syncService.statsServiceListener();
    syncService._startPeriodicSyncTimer();
    // Note: no startup bootstrap is enqueued here. The original cron
    // implementation enqueued a synthetic request on every tick so the
    // cron had something to do; in the on-demand trigger model the
    // queue should sit idle until a real trigger (an app `sync()` call
    // or a stats notification) arrives. The `hasHadNoSyncRequests`
    // flag is preserved for any callers that still inspect it.
    return syncService;
  }

  void _startPeriodicSyncTimer() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      if (isStopped) return;
      final last = lastSyncCompletedAt;
      if (last == null ||
          DateTime.now().toUtc().difference(last) > _periodicSyncInterval) {
        _logger.finer(
            'Periodic safety-net timer firing sync (last completed: $last)');
        sync();
      } else {
        _logger.finest(
            'Periodic safety-net timer skipped (last completed: $last)');
      }
    });
  }

  SyncServiceImpl._(this._atClient, this._remoteSecondary) {
    _logger = AtSignLogger('SyncService (${_atClient.getCurrentAtSign()})');
    _lastReceivedServerCommitIdAtKey =
        AtKey.local('lastreceivedservercommitid', currentAtSign).build();
    _skipDeletesUntilCommitId =
        AtKey.local('skipdeletesuntil', currentAtSign).build();
    atKeyDecryptionManager = AtKeyDecryptionManager(_atClient);
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

  /// Listens on stats notification sent by the cloud secondary server.
  ///
  /// Every well-formed notification promotes the cached
  /// [_latestKnownServerCommitId] (monotonically — see
  /// [_promoteServerCommitId]) and unconditionally enqueues a
  /// sync request. The actual
  /// "is sync work needed?" decision is made by
  /// [processSyncRequests] via [_isInSync], which considers BOTH
  /// pull-side (server has new commits) AND push-side (local writes
  /// awaiting upload) work. A previous local pre-filter here gated
  /// only on pull-side progress
  /// (`notification.value > lastReceivedServerCommitId`); that
  /// suppressed sync attempts whenever local writes were pending
  /// but the server had not advanced, leaving those writes stuck on
  /// disk until some unrelated trigger fired.
  @visibleForTesting
  Future<void> statsServiceListener() async {
    _statsNotificationSubscription = _atClient.notificationService
        .subscribe(regex: 'statsNotification')
        .listen((notification) async {
      _logger.finer('RCVD: stats notification in sync: ${notification.value}');
      final raw = notification.value;
      if (raw == null) return;
      final int observedServerCommitId;
      try {
        observedServerCommitId = int.parse(raw);
      } on FormatException {
        _logger.warning('statsServiceListener: malformed commitId "$raw"');
        return;
      }
      _promoteServerCommitId(observedServerCommitId);
      final syncRequest = SyncRequest()
        ..onDone = _onDone
        ..onError = _onError
        ..requestSource = SyncRequestSource.system
        ..requestedOn = DateTime.now().toUtc()
        ..result = SyncResult();
      _addSyncRequestToQueue(syncRequest);
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
  Future<void> processSyncRequests() async {
    _logger.finest('in _processSyncRequests');
    if (isStopped) {
      _logger.info('processSyncRequests: service is stopped; ignoring');
      return;
    }
    if (_processInProgress || _syncInProgress) {
      // In the on-demand trigger model every enqueue (and every drain
      // tail) calls processSyncRequests, so this branch fires
      // routinely. Log only — no SyncProgress event, since "I tried to
      // start a sync but one was already running" is not interesting
      // to listeners and would amplify their event count linearly with
      // queue activity.
      _logger.finer('processSyncRequests: another sync in progress');
      return;
    }
    if (syncRequests.isEmpty) {
      _logger.finest('processSyncRequests: queue empty; nothing to do');
      return;
    }
    // Claim the entry guard BEFORE awaiting anything so concurrent
    // triggers (now arriving on every enqueue) can't both pass the
    // guard above and race into the body. We use a separate flag from
    // _syncInProgress because _isInSync short-circuits on the latter.
    _processInProgress = true;
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
        _informSyncProgress(SyncProgress()
          ..syncStatus = SyncStatus.success
          ..startedAt = DateTime.now().toUtc()
          ..message = 'server and local are in sync');
        return;
      }

      _syncInProgress = true;
      int serverCommitId = await _getServerCommitId();
      final localCommitIdBeforeSync = await _getLocalCommitId();

      // Hint for the casual reader - main sync algorithm is in [syncInternal]
      final syncResult = await syncInternal(serverCommitId, syncRequest,
          localCommitIdBeforeSync: localCommitIdBeforeSync);

      _syncComplete(syncRequest);
      serverCommitId = await _getServerCommitId();
      final localCommitId = await _getLocalCommitId();

      _informSyncProgress(
          SyncProgress()
            ..syncStatus = syncResult.syncStatus
            ..startedAt = DateTime.now().toUtc()
            ..message = 'Sync complete (${syncResult.syncStatus})'
            ..keyInfoList = syncResult.keyInfoList,
          localCommitIdBeforeSync: localCommitIdBeforeSync,
          localCommitId: localCommitId,
          serverCommitId: serverCommitId);
      _syncInProgress = false;
    } on AtException catch (e) {
      e.stack(AtChainedException(Intent.syncData,
          ExceptionScenario.remoteVerbExecutionFailed, e.message));
      _logger.warning(
          'Exception in sync ${syncRequest.id}. Reason: ${e.getTraceMessage()}');
      final wrapped = AtExceptionManager.createException(e);
      syncRequest.result!.atClientException = wrapped;
      _syncError(syncRequest);
      _syncInProgress = false;
      _informSyncProgress(SyncProgress()
        ..syncStatus = SyncStatus.failure
        ..startedAt = DateTime.now().toUtc()
        ..message = 'Exception: $e'
        ..atClientException = wrapped);
    } catch (e) {
      // Catch-all: with on-demand triggering, an unhandled exception
      // from the sync path would become an unhandled async error and
      // fail tests / propagate noise. Surface it as a failure
      // SyncProgress event so listeners see it like any other sync
      // failure.
      _logger.warning(
          'Unexpected exception in sync ${syncRequest.id}. Reason: $e');
      final wrapped = AtClientException.message('$e');
      syncRequest.result!.atClientException = wrapped;
      _syncError(syncRequest);
      _syncInProgress = false;
      _informSyncProgress(SyncProgress()
        ..syncStatus = SyncStatus.failure
        ..startedAt = DateTime.now().toUtc()
        ..message = 'Unexpected exception: $e'
        ..atClientException = wrapped);
    } finally {
      _processInProgress = false;
      lastSyncCompletedAt = DateTime.now().toUtc();
      _drainQueueIfPending();
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
    return syncRequests.firstWhere(
        (syncRequest) =>
            syncRequest.requestSource == SyncRequestSource.app &&
            syncRequest.onDone != null,
        orElse: () => syncRequests.removeFirst());
  }

  void _syncError(SyncRequest syncRequest) {
    _safeInvokeOnError(syncRequest);
  }

  /// Calls [request.onError] (if non-null) with [request.result],
  /// wrapping the callback in a try-catch and logging anything
  /// thrown. The queue's eviction / drain / completion flows must
  /// not be derailed by a misbehaving caller-supplied callback —
  /// neither a single overflow nor a service stop should fail
  /// because one onError handler threw.
  ///
  /// Caller is responsible for populating [request.result] with the
  /// failure status and exception before calling.
  void _safeInvokeOnError(SyncRequest request) {
    if (request.onError == null) return;
    try {
      request.onError!(request.result);
    } catch (e) {
      _logger.warning('SyncRequest.onError threw and was swallowed: $e');
    }
  }

  void _syncComplete(SyncRequest syncRequest) {
    syncRequest.result!.lastSyncedOn = DateTime.now().toUtc();
    _logger.info(
        'Inside syncComplete. syncRequest.requestSource : ${syncRequest.requestSource}; syncRequest.onDone : ${syncRequest.onDone}');
    // If specific onDone callback is set, call specific onDone callback,
    // else call the global onDone callback.
    if (syncRequest.onDone != null &&
        syncRequest.requestSource == SyncRequestSource.app) {
      _logger.info('Sending result to onDone callback');
      syncRequest.onDone!(syncRequest.result);
    } else if (onDone != null) {
      onDone!(syncRequest.result);
    }
    _clearQueue(alreadyHandled: syncRequest);
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
    if (isStopped) {
      _logger.finer('_addSyncRequestToQueue: service is stopped; ignoring');
      return;
    }
    hasHadNoSyncRequests = false;
    if (syncRequests.length == queueSize) {
      // Drop-oldest sliding window: evict the head, not the tail. The
      // newest request is always retained (it represents the most
      // recent caller's intent to sync). The evicted request gets
      // an explicit onError invocation so its caller isn't left
      // waiting indefinitely on a callback that will never fire.
      final evicted = syncRequests.removeFirst();
      evicted.result ??= SyncResult();
      evicted.result!
        ..syncStatus = SyncStatus.failure
        ..atClientException = AtClientException(
          error_codes['AtClientException'],
          'Sync request evicted: queue at capacity ($queueSize); '
          'superseded by a newer sync request',
        );
      _safeInvokeOnError(evicted);
    }
    syncRequests.addLast(syncRequest);
    // Trigger a sync run on the next microtask. Deferring (rather than
    // calling synchronously) lets a burst of successive enqueues all
    // land in the queue before the first run starts consuming it, and
    // keeps `_addSyncRequestToQueue` itself free of side effects on
    // `_syncInProgress`. The _syncInProgress / isStopped guards inside
    // processSyncRequests make the call a cheap no-op when a run is
    // already active or the service has been stopped.
    scheduleMicrotask(() {
      unawaited(processSyncRequests());
    });
  }

  /// Schedules a follow-up [processSyncRequests] run if the queue is
  /// non-empty. Called at the end of each completed run so requests
  /// that arrived during the run aren't stranded. The microtask
  /// scheduling lets the in-flight `await` chain return first.
  void _drainQueueIfPending() {
    if (isStopped || syncRequests.isEmpty) return;
    scheduleMicrotask(() {
      unawaited(processSyncRequests());
    });
  }

  /// Drains the queue at the end of a successful sync run. Each
  /// remaining request — every queued sync intent that wasn't the
  /// one chosen for processing — is conceptually answered by the
  /// run that just completed (it brought local up to date), so we
  /// fire `onError` on each with a "superseded" failure rather than
  /// leaving its callback dangling forever.
  ///
  /// **Tail-of-burst handling**: under the post-`distributed-tickling-
  /// moler` design, "what to push" is owned by `LocalSecondary`'s
  /// `AtSyncQueue`, not by this request queue. A late-arriving local
  /// write (one whose `_update` / `_delete` enqueue lands during a
  /// running round) lives in the sync-queue Hive box; the next
  /// `processSyncRequests` round peeks the queue from a fresh
  /// snapshot and drains those entries. We therefore no longer need
  /// the per-source retention logic that briefly lived here at
  /// `de48210bf` — clearing wholesale is correct again.
  ///
  /// The just-processed request's `onDone` has already fired by the
  /// time this is called from [_syncComplete]; passing it as
  /// [alreadyHandled] keeps it from also being notified via `onError`
  /// here. Identity comparison is exact (`identical`) so only the
  /// specific in-flight instance is skipped.
  void _clearQueue({SyncRequest? alreadyHandled}) {
    _logger.finer('Clearing sync queue');
    final exception = AtClientException(
      error_codes['AtClientException'],
      'Sync request superseded by a coalesced sync run that just '
      'completed',
    );
    while (syncRequests.isNotEmpty) {
      final r = syncRequests.removeFirst();
      if (identical(r, alreadyHandled)) continue;
      r.result ??= SyncResult();
      r.result!
        ..syncStatus = SyncStatus.failure
        ..atClientException = exception;
      _safeInvokeOnError(r);
    }
  }

  @visibleForTesting
  Future<SyncResult> syncInternal(int serverCommitId, SyncRequest syncRequest,
      {int? localCommitIdBeforeSync}) async {
    var syncResult = syncRequest.result!;
    _logger.finer('Sync in progress');
    final localSecondary = _atClient.getLocalSecondary()!;
    // Snapshot of pending-push atKeys at sync-round start. Used by
    // [_syncFromServer] for conflict detection (a server-pulled key
    // is in conflict iff it's in this snapshot — i.e. we have a
    // pending local write for it). Pre-`decouple-sync-from-commit-log`
    // this snapshot was the commit log's `unCommittedEntries` list;
    // the new sync queue carries the same information directly.
    final pendingPushAtKeys =
        Set<String>.from(await localSecondary.peekSyncQueue());
    var lastReceivedServerCommitId = await getLastReceivedServerCommitId();
    if (serverCommitId > lastReceivedServerCommitId) {
      _logger.finer('Pulling changes into local secondary'
          ' | lastReceivedServerCommitId $lastReceivedServerCommitId'
          ' | serverCommitId $serverCommitId');
      // Hint to casual reader: This is where we sync new changes from the server to this client
      final keyInfoList = await _syncFromServer(
          serverCommitId, lastReceivedServerCommitId, pendingPushAtKeys,
          localCommitIdBeforeSync: localCommitIdBeforeSync);
      syncResult.keyInfoList.addAll(keyInfoList);
    }
    final pushQueueSize = await localSecondary.syncQueueSize;
    if (pushQueueSize > 0) {
      _logger.finer(
          'Found $pushQueueSize pending atKeys in the sync queue; pushing.');
      // Hint to casual reader: This is where we sync new changes from this client to the server
      final keyInfoList = await _pushFromSyncQueue();
      syncResult.keyInfoList.addAll(keyInfoList);
    }
    syncResult.lastSyncedOn = DateTime.now().toUtc();
    syncResult.syncStatus = SyncStatus.success;
    return syncResult;
  }

  /// Drains the [LocalSecondary]'s sync queue, pushing each pending
  /// atKey to the cloud secondary as part of a batched `batch:` verb.
  ///
  /// Per round:
  /// 1. Peek the next [AtClientPreference.syncBatchSize] atKeys from
  ///    the queue (FIFO).
  /// 2. For each, read the queued op (and value+metadata from the
  ///    keystore for non-DELETE ops). Skip + remove the queue entry
  ///    if the keystore value is missing — race-tolerated handling
  ///    of a write that landed between queue-write and keystore-write
  ///    timing windows (rare, but the alternative is leaking queue
  ///    entries forever).
  /// 3. Build a `BatchRequest` list and send via [sendBatch] (single
  ///    network round-trip per batch — preserves the pre-refactor
  ///    network-roundtrip savings under heavy load).
  /// 4. For each per-entry response: on success, remove from the
  ///    queue and promote `_latestKnownServerCommitId`. On failure,
  ///    leave in queue for retry on the next round.
  /// 5. Emit a per-batch [SyncStatus.inProgress] event so listeners
  ///    can render "pushed N of M" progress.
  /// 6. Repeat until the queue is empty.
  ///
  /// Returns the per-entry [KeyInfo] list for the round (used by
  /// [SyncProgress.keyInfoList] in the terminal success event).
  Future<List<KeyInfo>> _pushFromSyncQueue() async {
    final localSecondary = _atClient.getLocalSecondary()!;
    final batchSize = _atClient.getPreferences()!.syncBatchSize;
    final keyInfoList = <KeyInfo>[];
    var batchesDone = 0;
    while (true) {
      final atKeys = await localSecondary.peekSyncQueue(limit: batchSize);
      if (atKeys.isEmpty) break;
      // Snapshot the queue size BEFORE this batch so the
      // no-progress guard at the bottom can detect "the entries
      // we just tried didn't get removed" without conflating it
      // with "the queue is large because more writes arrived".
      final queueSizeBefore = await localSecondary.syncQueueSize;
      // Build the batch. Order in `batchRequests` mirrors the order
      // we got from `peekSyncQueue` — and the response comes back
      // 1-indexed by batch id, so index N-1 in our list is the entry
      // for batch id N. Track the source atKey + op alongside so we
      // can correlate the response without re-parsing the wire.
      final batchRequests = <BatchRequest>[];
      final batchSources = <_BatchSource>[];
      for (final atKey in atKeys) {
        final entry = await localSecondary.readSyncQueueEntry(atKey);
        if (entry == null) {
          // The queue says we should push this atKey but the
          // persisted record is gone (rare race — concurrent remove,
          // or replay-time corruption). Drop it.
          _logger.warning(
              'sync queue race: $atKey missing persisted record; removing');
          await localSecondary.removeFromSyncQueue(atKey);
          continue;
        }
        final String command;
        try {
          command = await _buildCommandFromQueueEntry(atKey, entry.op);
        } on KeyNotFoundException {
          // The keystore doesn't have a value for this atKey
          // (UPDATE / UPDATE_ALL / UPDATE_META). This is the race
          // mentioned in the plan: queue write committed but the
          // backing keystore write never landed (a crash between
          // them). Drop the queue entry — there's nothing we can
          // push, and the user-level write was lost anyway.
          _logger
              .info('keystore miss for $atKey on push; dropping queue entry');
          await localSecondary.removeFromSyncQueue(atKey);
          continue;
        }
        final batchId = batchRequests.length + 1;
        batchRequests
            .add(BatchRequest(batchId, VerbUtil.replaceNewline(command)));
        batchSources.add(_BatchSource(
          atKey: atKey,
          op: entry.op,
          commitLogSeqNum: entry.commitLogSeqNum,
        ));
      }
      if (batchRequests.isEmpty) {
        // Every queued atKey we pulled was a phantom; loop and try
        // the next batch (the queue may still have more).
        continue;
      }
      List<dynamic> batchResponse;
      try {
        batchResponse = await sendBatch(batchRequests);
      } on Exception catch (e) {
        // Network or auth failure for the whole batch. Leave queue
        // entries in place — next round retries.
        final cause = (e is AtException) ? e.getTraceMessage() : e.toString();
        _logger.severe('sendBatch failed: $cause');
        return keyInfoList;
      }
      for (final entry in batchResponse) {
        try {
          final batchId = entry['id'] as int;
          final serverResponse = entry['response'];
          final responseObject = Response.fromJson(serverResponse);
          final source = batchSources.elementAt(batchId - 1);
          var commitId = -1;
          if (responseObject.data != null) {
            commitId = int.parse(responseObject.data!);
          }
          if (commitId == -1) {
            _logger.severe(
                '${source.op} for key ${source.atKey} failed. Error code '
                '${responseObject.errorCode} error message '
                '${responseObject.errorMessage}');
            // Leave in queue for retry. Don't remove.
            continue;
          }
          _promoteServerCommitId(commitId);
          // Track the high-water mark of OUR successful pushes
          // separately from the broader server cursor so
          // [_getLocalCommitId] reflects "our writes the server has
          // acked" the way the pre-refactor commit-log scan did.
          if (_highestPushedCommitId == null ||
              commitId > _highestPushedCommitId!) {
            _highestPushedCommitId = commitId;
          }
          // Back-write the server-assigned commitId onto the
          // commit-log entry that the originating local write
          // produced. Required by the commit-log compaction job
          // (which only compacts entries with non-null commitId) and
          // by `SyncUtil.getLastSyncedEntry`. The seqNum threaded
          // through the sync queue gives O(1) lookup; missing seqNum
          // (older queue entries / skipCommit writes) falls back to
          // a commit-log scan.
          await _backWriteCommitIdForPushedEntry(
              source.atKey, commitId, source.commitLogSeqNum);
          await localSecondary.removeFromSyncQueue(source.atKey);
          keyInfoList.add(KeyInfo(
            source.atKey,
            SyncDirection.localToRemote,
            _syncQueueOpToCommitOp(source.op),
          ));
        } on Exception catch (e) {
          final cause = (e is AtException) ? e.getTraceMessage() : e.toString();
          _logger.severe(
              'exception processing batch response entry $entry: $cause');
        }
      }
      batchesDone++;
      _informSyncProgress(
        SyncProgress()
          ..syncStatus = SyncStatus.inProgress
          ..startedAt = DateTime.now().toUtc()
          ..message = 'Push batch $batchesDone applied; '
              '${await localSecondary.syncQueueSize} pending',
        localCommitId: _latestKnownServerCommitId,
        serverCommitId: _latestKnownServerCommitId,
      );
      // Defensive: if every entry in this batch failed (e.g. a
      // server-side per-key authorization issue), the entries we
      // tried weren't removed from the queue. Compare against the
      // pre-batch snapshot — if size hasn't dropped at all (after
      // accounting for any new writes that arrived during the
      // batch), bail out and let a subsequent round retry.
      // Concurrent writes during the batch can keep `pendingNow`
      // ≥ `queueSizeBefore`, which is fine — those new writes will
      // be drained when the next round picks them up; what matters
      // here is whether the in-batch entries themselves got
      // removed.
      final pendingNow = await localSecondary.syncQueueSize;
      final pendingFront = await localSecondary.peekSyncQueue(limit: 1);
      final atKeysSet = atKeys.toSet();
      final allBatchKeysStillPresent =
          pendingFront.isNotEmpty && atKeysSet.contains(pendingFront.first);
      if (pendingNow > 0 &&
          pendingNow >= queueSizeBefore &&
          allBatchKeysStillPresent) {
        _logger.warning('sync queue: $pendingNow pending after batch (was '
            '$queueSizeBefore); none of the in-batch entries were '
            'removed — bailing out, will retry next round');
        break;
      }
    }
    return keyInfoList;
  }

  /// Builds the wire command for one queued atKey + op. Shape
  /// matches the pre-refactor `_getCommand` (CommitOp variant), so
  /// the at_server side parses it identically.
  Future<String> _buildCommandFromQueueEntry(
      String atKey, SyncQueueOp op) async {
    final keyStore = _atClient.getLocalSecondary()!.keyStore!;
    switch (op) {
      case SyncQueueOp.delete:
        return 'delete:$atKey';
      case SyncQueueOp.update:
        final value = await keyStore.get(atKey);
        return 'update:$atKey ${value?.data}';
      case SyncQueueOp.updateMeta:
        final metaData = await keyStore.getMeta(atKey);
        final keyWithMeta =
            metaData != null ? '$atKey${_metadataToString(metaData)}' : atKey;
        return 'update:meta:$keyWithMeta';
      case SyncQueueOp.updateAll:
        final AtData value = await keyStore.get(atKey);
        final keyGen = '${_metadataToString(value.metaData)}:$atKey';
        return 'update$keyGen ${value.data}';
    }
  }

  /// Maps a [SyncQueueOp] back to its [CommitOp] equivalent so we
  /// can populate the [KeyInfo.commitOp] field in
  /// [SyncProgress.keyInfoList] events the same way the
  /// pre-refactor code did. Kept symmetric with the converse map
  /// in `LocalSecondary._update` / `_delete`.
  CommitOp _syncQueueOpToCommitOp(SyncQueueOp op) {
    switch (op) {
      case SyncQueueOp.update:
        return CommitOp.UPDATE;
      case SyncQueueOp.updateAll:
        return CommitOp.UPDATE_ALL;
      case SyncQueueOp.updateMeta:
        return CommitOp.UPDATE_META;
      case SyncQueueOp.delete:
        return CommitOp.DELETE;
    }
  }

  /// Syncs the cloud secondary changes to local secondary.
  ///
  /// [pendingPushAtKeys] is a snapshot taken at sync-round start of
  /// the atKeys that have a pending client→server write in
  /// `LocalSecondary`'s sync queue. Used here for conflict detection:
  /// a server-pulled key is in conflict iff it appears in this set
  /// (i.e. we have a local write the server doesn't know about).
  /// Pre-`decouple-sync-from-commit-log` this was a `List<CommitEntry>`
  /// pulled from the commit log; the new sync queue carries the same
  /// information directly.
  Future<List<KeyInfo>> _syncFromServer(int serverCommitId,
      int lastReceivedServerCommitId, Set<String> pendingPushAtKeys,
      {int? localCommitIdBeforeSync}) async {
    // Iterates until serverCommitId is greater than lastReceivedServerCommitId.
    // replacing localCommitId with lastReceivedServerCommitId fixes infinite loop issue
    // in certain scenarios e.g server has a commit entry that need not be synced on client side,
    // server has delete commit entry and the key is not present on local keystore
    List<KeyInfo> keyInfoList = [];
    try {
      int? skipDeletesUntil = await setAndGetSkipDeletesUntil(
          localCommitIdBeforeSync, serverCommitId);

      while (serverCommitId > lastReceivedServerCommitId) {
        _sendTelemetry('_syncFromServer.whileLoop', {
          "serverCommitId": serverCommitId,
          "lastReceivedServerCommitId": lastReceivedServerCommitId
        });
        List<dynamic> listOfCommitEntriesFromServer =
            await _getEntriesToSyncFromServer(
                lastReceivedServerCommitId, serverCommitId,
                localCommitIdBeforeSync: localCommitIdBeforeSync,
                skipDeletesUntil: skipDeletesUntil);
        if (listOfCommitEntriesFromServer.isEmpty) {
          // Server walked the full (lastReceivedServerCommitId,
          // serverCommitId] range and returned no entries for this
          // client — every commit in that window was filtered out
          // server-side (apkam namespace scope, syncRegex, or
          // skipDeletesUntil). Advance the cursor to serverCommitId
          // (the sync-start snapshot, NOT the live
          // [_latestKnownServerCommitId], which may have advanced
          // into commits we haven't yet examined) so subsequent
          // rounds no-op until the server moves past it, instead
          // of re-probing the same filtered range every round.
          _logger.finer(
              'sync response is empty | advancing cursor past filtered range | '
              'local commitID: $lastReceivedServerCommitId -> $serverCommitId | '
              'server commitID: $serverCommitId');
          lastReceivedServerCommitId = serverCommitId;
          _promoteServerCommitId(lastReceivedServerCommitId);
          break;
        }
        // Iterates over each commit entry. If the serverCommitEntry's
        // atKey is in the [pendingPushAtKeys] set we have a local
        // write for the same key — record a conflict and don't
        // overwrite the local copy.
        for (dynamic serverCommitEntry in listOfCommitEntriesFromServer) {
          final serverAtKey = serverCommitEntry['atKey'].toString().trim();
          final hasLocalConflict = pendingPushAtKeys.contains(serverAtKey);
          if (hasLocalConflict) {
            lastReceivedServerCommitId =
                _parseToInteger(serverCommitEntry['commitId']);
            _promoteServerCommitId(lastReceivedServerCommitId);
            _logger.finer(
                'Server commitEntry ${serverCommitEntry['atKey']} exists in '
                'uncommitted entries. So skipping the commit entry and '
                'updating the lastReceivedServerCommitId to $lastReceivedServerCommitId');
            ConflictInfo? conflictInfo =
                await _setConflictInfo(serverCommitEntry);
            final keyInfo = KeyInfo(
                serverCommitEntry['atKey'],
                SyncDirection.remoteToLocal,
                convertCommitOpSymbolToEnum(serverCommitEntry['operation']))
              ..conflictInfo = conflictInfo;
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
          _promoteServerCommitId(lastReceivedServerCommitId);
          await _processServerCommitEntry(serverCommitEntry, keyInfoList);
          _logger.finest(
              'Updating lastReceivedServerCommitId to $lastReceivedServerCommitId');
        }
        // Per-batch progress event: lets long syncs (e.g. server at
        // 20000, local at 1000) report incremental advancement to
        // listeners (and to `waitUntilCaughtUp`) instead of staying
        // silent until the entire pull finishes.
        _informSyncProgress(
            SyncProgress()
              ..syncStatus = SyncStatus.inProgress
              ..startedAt = DateTime.now().toUtc()
              ..message =
                  'Pull batch applied: $lastReceivedServerCommitId / $serverCommitId',
            localCommitIdBeforeSync: localCommitIdBeforeSync,
            localCommitId: lastReceivedServerCommitId,
            serverCommitId: serverCommitId);
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

  Future<void> _processServerCommitEntry(
      Map serverCommitEntry, List<KeyInfo> keyInfoList) async {
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
    } catch (e) {
      _sendTelemetry('_syncFromServer.forEachEntry.exception', {"e": e});
      _logger.severe(
          'Exception: $e while syncing entry to local ${jsonEncode(serverCommitEntry)}');
    }
  }

  /// Takes the last received server commit id and fetches the entries that are above the given
  /// commit-id to sync into the local keystore. If [skipDeletesUntil] is set then delete commit entries
  /// with commit-id greater than [skipDeletesUntil] will not be synced from server.
  Future<List<dynamic>> _getEntriesToSyncFromServer(
      int lastReceivedServerCommitId, int serverCommitId,
      {int? localCommitIdBeforeSync, int? skipDeletesUntil}) async {
    // Sync verb syntax has to be changed before removing these deprecations
    var syncBuilder = SyncVerbBuilder()
      ..commitId = lastReceivedServerCommitId
      ..limit = _atClient.getPreferences()!.syncPageLimit
      ..regex = _atClient.getPreferences()!.syncRegex;
    if (_shouldSkipDeletes(skipDeletesUntil, serverCommitId)) {
      syncBuilder.skipDeletesUntil = skipDeletesUntil;
    }

    _logger.finer('syncBuilder ${syncBuilder.buildCommand()}');
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
    _logger.finest('syncResponse $syncResponseJson');
    return syncResponseJson;
  }

  @visibleForTesting

  /// When a new client is authenticated, set the [_skipDeletesUntilCommitId] to the supplied `serverCommitId` for initial sync
  /// If initial sync is interrupted before client fully syncs from the server and client authenticates again, retrieve
  /// [_skipDeletesUntilCommitId] from local secondary and return
  Future<int?> setAndGetSkipDeletesUntil(
      int? localCommitIdBeforeSync, int serverCommitId) async {
    if (localCommitIdBeforeSync == -1) {
      await _atClient.put(_skipDeletesUntilCommitId, serverCommitId.toString());
      return serverCommitId;
    }
    try {
      return int.parse((await _atClient.get(_skipDeletesUntilCommitId)).value);
    } on AtKeyNotFoundException {
      // do nothing
    }
    return null;
  }

  bool _shouldSkipDeletes(int? skipDeletesUntil, int serverCommitId) {
    if (skipDeletesUntil == null) {
      return false;
    }
    return serverCommitId >= skipDeletesUntil;
  }

  Future<ConflictInfo?> _setConflictInfo(final Map serverCommitEntry) async {
    String key = serverCommitEntry['atKey'];
    // publickey.<atsign>@<currentatsign> is used to store the public key of
    // other atsign. The value is not encrypted.
    // The keys starting with publickey. and keys that contain shared_key
    // (@someone:shared_key@me, shared_key.someone@me) are the reserved keys
    // and do not require actions. Hence skipping from checking conflict resolution.
    if (key.startsWith('publickey.') ||
        key.startsWith(encryptedSharedKeyMatcher) ||
        key.startsWith('cached:')) {
      _logger.finer('$key found in conflict resolution, returning null');
      return null;
    }

    // temporary fix to add @ to sharedBy. permanent fix should be in AtKey.fromString
    AtKey clientAtKey = AtKey.fromString(key);
    if (clientAtKey.sharedBy != null) {
      clientAtKey.sharedBy = AtUtils.fixAtSign(clientAtKey.sharedBy!);
    }
    final conflictInfo = ConflictInfo();
    try {
      AtValue localAtValue;
      // For a conflicting key, if an uncommitted entry is of CommitOp.Delete, then
      // key will not exist in Key-Store. On KeyNotFoundException, return null.
      try {
        localAtValue = await _atClient.get(clientAtKey);
      } on KeyNotFoundException {
        return null;
      } on AtKeyNotFoundException {
        return null;
      }
      if (clientAtKey is PublicKey || key.contains('public:')) {
        final serverValue = serverCommitEntry['value'];
        if (localAtValue.value != serverValue) {
          conflictInfo.localValue = localAtValue.value;
          conflictInfo.remoteValue = serverValue;
        }
        return conflictInfo;
      }
      final serverAtKey = AtKey.fromString(clientAtKey.toString());
      _setMetadataFromCommitEntry(serverAtKey.metadata, serverCommitEntry);
      final serverEncryptedValue = serverCommitEntry['value'];
      final serverMetaData = serverCommitEntry['metadata'];
      if (serverMetaData != null &&
          serverMetaData[AtConstants.isEncrypted] == "true") {
        final decrypter = atKeyDecryptionManager.get(serverAtKey);
        // ignore: prefer_typing_uninitialized_variables
        var serverDecryptedValue;
        if (serverEncryptedValue != null && serverEncryptedValue.isNotEmpty) {
          serverDecryptedValue =
              await decrypter.decrypt(serverAtKey, serverEncryptedValue);
        }
        if (localAtValue.value != serverDecryptedValue) {
          conflictInfo.localValue = localAtValue.value;
          conflictInfo.remoteValue = serverDecryptedValue;
        }
      }
      return conflictInfo;
    } catch (e, st) {
      conflictInfo.errorOrExceptionMessage =
          'Exception occurred when setting conflict info for $clientAtKey | $e';
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
        _logger.info(
            '${entry.atKey} is no longer in keystore. Skipping sync for it.');
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
      try {
        await syncUtil.removeCommitEntry(commitEntry.key, currentAtSign);
      } catch (e) {
        _logger.shout('Exception $e - commitEntry is $commitEntry');
      }
    }
    removeUncommittedEntriesList.clear();
    return batchRequests;
  }

  Future<String> _getCommand(CommitEntry entry) async {
    if (entry.operation == null) {
      throw StateError('CommitEntry operation is null : $entry');
    }
    late String command;
    // ignore: missing_enum_constant_in_switch
    switch (entry.operation!) {
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
    if (metadata.pubKeyHash != null) {
      metadataStr +=
          ':${AtConstants.sharedWithPublicKeyHash}:${metadata.pubKeyHash?.hash}';
      metadataStr +=
          ':${AtConstants.sharedWithPublicKeyHashingAlgo}:${metadata.pubKeyHash?.hashingAlgo}';
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
    try {
      // Force-fresh: this is a decision point — staleness here would
      // give the caller a false "in sync" answer when a recent
      // direct-to-server change hasn't propagated to the cache yet.
      final serverCommitId = await _getServerCommitId(forceFresh: true);
      final lastReceivedServerCommitId = await getLastReceivedServerCommitId();
      final pendingPushCount =
          await _atClient.getLocalSecondary()!.syncQueueSize;
      _logger.finest('public isInSync: serverCommitId=$serverCommitId '
          'lastReceivedServerCommitId=$lastReceivedServerCommitId '
          'pendingPushCount=$pendingPushCount');
      // We're "in sync" iff the client→server queue is empty AND the
      // server hasn't moved past what we've already pulled. Same
      // shape as the private [_isInSync] used by `processSyncRequests`
      // — kept aligned so app-level `isInSync()` callers see the
      // same answer the round-decision sees.
      return pendingPushCount == 0 &&
          lastReceivedServerCommitId == serverCommitId;
    } on Exception catch (e) {
      var cause = (e is AtException) ? e.getTraceMessage() : e.toString();
      _logger.severe('exception in isInSync $cause');
      throw AtClientException.message(e.toString());
    }
  }

  Future<bool> _isInSync() async {
    if (_syncInProgress) {
      _logger.finest('*** isInSync..sync in progress');
      return true;
    }
    // Force-fresh: see [_getServerCommitId] doc — we're deciding whether
    // sync work is needed; a stale cache would skip the run.
    var serverCommitId = await _getServerCommitId(forceFresh: true);
    var lastReceivedServerCommitId = await getLastReceivedServerCommitId();
    final pendingPushCount = await _atClient.getLocalSecondary()!.syncQueueSize;
    _logger.finest('server commit id: $serverCommitId '
        'lastReceivedServerCommitId: $lastReceivedServerCommitId '
        'pending push count: $pendingPushCount');
    // We're "in sync" iff the client→server queue is empty AND the
    // server hasn't moved past what we've already pulled. The
    // client-side push backlog now lives in `LocalSecondary`'s
    // sync queue (was: `unCommittedEntries` from the commit log).
    return pendingPushCount == 0 &&
        lastReceivedServerCommitId == serverCommitId;
  }

  /// Returns the cloud secondary latest commit id. if null, returns -1.
  /// Monotonically promotes the cached [_latestKnownServerCommitId]
  /// to [observed] when it represents progress. Centralised so the
  /// three update paths (stats notifications, push batch responses,
  /// pull entries) share the same monotonic guard — out-of-order
  /// arrivals can't rewind the cache.
  void _promoteServerCommitId(int observed) {
    final current = _latestKnownServerCommitId;
    if (current == null || observed > current) {
      _latestKnownServerCommitId = observed;
    }
  }

  /// Returns the latest known server commit id. With [forceFresh: false]
  /// (the default) the cached value is returned when non-null; the
  /// cache is kept current by stats notifications, batch responses
  /// from `_syncToRemote`, and pulled entries from `_syncFromServer`.
  ///
  /// With [forceFresh: true] the cache is bypassed and a remote stats
  /// fetch is issued; the result is then written back into the cache
  /// (subject to the monotonic [_promoteServerCommitId] guard) so
  /// subsequent cached reads benefit from it.
  ///
  /// `forceFresh: true` is used by the sync-decision points
  /// ([isInSync] / [_isInSync]) — if a recent direct-to-server
  /// modification happened and the corresponding stats notification
  /// hasn't arrived yet, the cache is stale and would cause
  /// `processSyncRequests` to wrongly conclude "no work needed".
  ///
  /// Throws [AtLookUpException] if the remote secondary is not
  /// reachable.
  Future<int> _getServerCommitId({bool forceFresh = false}) async {
    if (!forceFresh) {
      final cached = _latestKnownServerCommitId;
      if (cached != null) {
        _logger.finer('Returning serverCommitId $cached (cached)');
        return cached;
      }
    }
    var fresh = await syncUtil.getLatestServerCommitId(
        _remoteSecondary, _atClient.getPreferences()!.syncRegex);
    // If server commit id is null, set to -1;
    fresh ??= -1;
    _promoteServerCommitId(fresh);
    _logger.info(
        'Returning serverCommitId $fresh ${forceFresh ? "(forced fresh)" : "(cold fetch)"}');
    return fresh;
  }

  @visibleForTesting
  Future<int> getLastReceivedServerCommitId() async {
    // If "lastReceivedServerCommitId" key exists, fetch the data and return the
    // last received server commit id. If not, return -1 (no pull has
    // ever applied to this client). Pre-`decouple-sync-from-commit-log`
    // this fell back to `_getLocalCommitId`; that fallback only made
    // sense when `_getLocalCommitId` read the local commit log (a
    // post-pull entry was a reasonable proxy for "last received
    // server cursor"). Post-refactor `_getLocalCommitId` itself
    // composes this method's value, so the fallback would recurse
    // and is no longer correct semantically.
    try {
      var response = await _atClient.get(_lastReceivedServerCommitIdAtKey);
      _logger.finer(
          'Returning lastReceivedServerCommitId from AtKey: ${response.value}');
      return int.parse(response.value);
    } on AtKeyNotFoundException {
      _logger.finer('lastReceivedServerCommitId AtKey not found. Returning -1');
      return -1;
    }
  }

  /// Returns the highest commit id this client has observed for ITS
  /// OWN view of server state — the union of:
  ///
  /// * [_highestPushedCommitId] — server commit ids assigned to our
  ///   successful pushes (see `_pushFromSyncQueue`).
  /// * `lastReceivedServerCommitId` — the cursor written after each
  ///   pull batch in `_syncFromServer`'s finally block.
  ///
  /// Returns `-1` when neither has ever advanced (truly fresh
  /// client). The `localCommitIdBeforeSync == -1` check uses this
  /// value to set the `isInitialSync` flag on the first round.
  ///
  /// Pre-`decouple-sync-from-commit-log` this number was the local
  /// commit log's max commitId, which naturally tracked both
  /// directions because `_pullToLocal` back-wrote the server-assigned
  /// commitId into each pulled entry. The refactor split push and
  /// pull bookkeeping; we recompose them here so the externally
  /// observed `localCommitId` (in `SyncProgress` events) keeps the
  /// same union semantic — the existing test harnesses
  /// (`FunctionalTestSyncService`, `E2ESyncService`) check
  /// `localCommitId == serverCommitId` as their "in sync" signal,
  /// which only holds with the union.
  ///
  /// Reads the cursor key inline rather than via
  /// [getLastReceivedServerCommitId] to keep the dependency one-way
  /// (callee → callee, not mutual).
  Future<int> _getLocalCommitId() async {
    final pushed = _highestPushedCommitId ?? -1;
    int pulled = -1;
    try {
      final response = await _atClient.get(_lastReceivedServerCommitIdAtKey);
      pulled = int.parse(response.value);
    } on AtKeyNotFoundException {
      // pulled stays -1
    }
    return pushed > pulled ? pushed : pulled;
  }

  @visibleForTesting
  dynamic sendBatch(List<BatchRequest> requests) async {
    var command = 'batch:';
    command += jsonEncode(requests);
    command += '\n';
    _logger.finer('Sending batch to sync: $command');
    var verbResult = await _remoteSecondary.executeCommand(command, auth: true);
    _logger.finer('batch result:$verbResult');
    if (verbResult != null) {
      verbResult = verbResult.replaceFirst(RegExp('^data:'), '');
    }
    return jsonDecode(verbResult!);
  }

  Future<void> _syncLocal(Map serverCommitEntry) async {
    switch (serverCommitEntry['operation']) {
      case '+':
      case '#':
      case '*':
        var builder = UpdateVerbBuilder()
          ..atKey = AtKey.fromString(serverCommitEntry['atKey'])
          ..value = serverCommitEntry['value'];
        builder.operation = AtConstants.updateAll;
        _setMetadataFromCommitEntry(builder.atKey.metadata, serverCommitEntry);
        await _pullToLocal(builder, serverCommitEntry, CommitOp.UPDATE_ALL);
        break;
      case '-':
        var builder = DeleteVerbBuilder()
          ..atKey = AtKey.fromString(serverCommitEntry['atKey']);
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

  void _setMetadataFromCommitEntry(Metadata md, Map serverCommitEntry) {
    var metaData = serverCommitEntry['metadata'];
    if (metaData != null && metaData.isNotEmpty) {
      if (metaData[AtConstants.ttl] != null) {
        md.ttl = int.parse(metaData[AtConstants.ttl]);
      }
      if (metaData[AtConstants.ttb] != null) {
        md.ttb = int.parse(metaData[AtConstants.ttb]);
      }
      if (metaData[AtConstants.ttr] != null) {
        md.ttr = int.parse(metaData[AtConstants.ttr]);
      }
      if (metaData[AtConstants.ccd] != null) {
        (metaData[AtConstants.ccd].toLowerCase() == 'true')
            ? md.ccd = true
            : md.ccd = false;
      }
      if (metaData[AtConstants.publicDataSignature] != null) {
        md.dataSignature = metaData[AtConstants.publicDataSignature];
      }
      if (metaData[AtConstants.isBinary] != null) {
        (metaData[AtConstants.isBinary].toLowerCase() == 'true')
            ? md.isBinary = true
            : md.isBinary = false;
      }
      if (metaData[AtConstants.isEncrypted] != null) {
        (metaData[AtConstants.isEncrypted].toLowerCase() == 'true')
            ? md.isEncrypted = true
            : md.isEncrypted = false;
      }
      if (metaData[AtConstants.sharedKeyEncrypted] != null) {
        md.sharedKeyEnc = metaData[AtConstants.sharedKeyEncrypted];
      }
      if (metaData[AtConstants.sharedWithPublicKeyCheckSum] != null) {
        md.pubKeyCS = metaData[AtConstants.sharedWithPublicKeyCheckSum];
      }
      if (metaData[AtConstants.sharedWithPublicKeyHash] != null) {
        Map pubKeyHash =
            jsonDecode(metaData[AtConstants.sharedWithPublicKeyHash]);
        md.pubKeyHash =
            PublicKeyHash(pubKeyHash['hash'], pubKeyHash['hashingAlgo']);
      }
      if (metaData[AtConstants.encoding] != null) {
        md.encoding = metaData[AtConstants.encoding];
      }
      if (metaData[AtConstants.encryptingKeyName] != null) {
        md.encKeyName = metaData[AtConstants.encryptingKeyName];
      }
      if (metaData[AtConstants.encryptingAlgo] != null) {
        md.encAlgo = metaData[AtConstants.encryptingAlgo];
      }
      if (metaData[AtConstants.ivOrNonce] != null) {
        md.ivNonce = metaData[AtConstants.ivOrNonce];
      }
      if (metaData[AtConstants.sharedKeyEncryptedEncryptingKeyName] != null) {
        md.skeEncKeyName =
            metaData[AtConstants.sharedKeyEncryptedEncryptingKeyName];
      }
      if (metaData[AtConstants.sharedKeyEncryptedEncryptingAlgo] != null) {
        md.skeEncAlgo = metaData[AtConstants.sharedKeyEncryptedEncryptingAlgo];
      }

      if (metaData[AtConstants.sharedWithPublicKeyHash] != null &&
          metaData[AtConstants.sharedWithPublicKeyHashingAlgo] != null) {
        md.pubKeyHash = PublicKeyHash(
            metaData[AtConstants.sharedWithPublicKeyHash],
            metaData[AtConstants.sharedWithPublicKeyHashingAlgo]);
      }
    }
  }

  Future<void> _pullToLocal(
      VerbBuilder builder, serverCommitEntry, CommitOp operation) async {
    String? verbResult;
    try {
      // `cameFromServer: true` flags this write as a server-replay so
      // `LocalSecondary` (post phase 4 of decouple-sync-from-commit-log)
      // skips enqueuing it for client→server sync — the server is
      // where this entry just came from. `sync: false` is the legacy
      // signal expressing the same intent against today's
      // `syncFromWrite` path; both stay in place during the
      // transition.
      verbResult = await _atClient.getLocalSecondary()!.executeVerb(
            builder,
            sync: false,
            cameFromServer: true,
          );
    } on UnAuthorizedException catch (e) {
      _logger.finer(
          'Failed to sync ${(builder as UpdateVerbBuilder).atKey.toString()} caused by ${e.toString()}');
    }
    if (verbResult == null) {
      return;
    }
    // Back-write the server-side commitId into the local commit-log
    // entry that `executeVerb` just appended. The new sync push path
    // no longer reads commit-log commitIds (it tracks
    // `_highestPushedCommitId` directly + `lastReceivedServerCommitId`
    // for the cursor) — but commit-log compaction still needs every
    // synced entry to carry a commitId (its `removeWhere(value.commitId
    // == null)` step would otherwise skip every server-pulled entry,
    // leaving the log to grow unboundedly). `SyncUtil.getLastSyncedEntry`
    // also still depends on this for the downstream functional tests
    // and any external consumers.
    final sequenceNumber = int.parse(verbResult.split(':')[1]);
    final commitEntry = await syncUtil.getCommitEntry(
        sequenceNumber, _atClient.getCurrentAtSign()!);
    if (commitEntry == null) {
      return;
    }
    commitEntry.operation = operation;
    final serverCommitId = serverCommitEntry['commitId'];
    if (serverCommitId == null) {
      return;
    }
    await syncUtil.updateCommitEntry(
        commitEntry, serverCommitId, _atClient.getCurrentAtSign()!);
  }

  /// Stamps the server-assigned [commitId] onto the commit-log entry
  /// that the local keystore op for [atKey] produced. Used by
  /// [_pushFromSyncQueue] after each successful per-entry batch
  /// response.
  ///
  /// **Fast path**: when [seqNum] is supplied (the keystore op's
  /// `Future<int?>` return value, threaded through the sync queue),
  /// the entry is fetched directly via [SyncUtil.getCommitEntry] —
  /// O(1).
  ///
  /// **Slow path**: when [seqNum] is null (older queue entries
  /// persisted before the field was added; or a `skipCommit` write
  /// whose op didn't append a commit-log entry — though those don't
  /// reach the sync queue), fall back to scanning the commit log for
  /// the latest entry matching [atKey] — O(N log N).
  ///
  /// The back-write is required by:
  /// - the commit-log compaction job (only compacts entries with
  ///   non-null commitId);
  /// - `SyncUtil.getLastSyncedEntry`, used by downstream functional
  ///   tests and external consumers.
  ///
  /// Best-effort: failures are logged at warning, not surfaced to
  /// the caller. Sync correctness doesn't depend on the back-write
  /// succeeding (the actual write reached the server; only the
  /// commit-log metadata is at stake).
  Future<void> _backWriteCommitIdForPushedEntry(
      String atKey, int commitId, int? seqNum) async {
    try {
      final atSign = _atClient.getCurrentAtSign()!;
      if (seqNum != null) {
        final entry = await syncUtil.getCommitEntry(seqNum, atSign);
        if (entry == null) {
          return;
        }
        await syncUtil.updateCommitEntry(entry, commitId, atSign);
        return;
      }
      final atCommitLog =
          await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);
      if (atCommitLog == null) {
        return;
      }
      final entry = await syncUtil.getLatestCommitEntry(atCommitLog, atKey);
      if (entry is NullCommitEntry) {
        return;
      }
      await syncUtil.updateCommitEntry(entry, commitId, atSign);
    } on Exception catch (e) {
      // Best-effort metadata update; sync correctness doesn't depend
      // on this back-write succeeding. Log and continue.
      final cause = (e is AtException) ? e.getTraceMessage() : e.toString();
      _logger.warning(
          'back-write of commitId $commitId for $atKey failed: $cause');
    }
  }

  @visibleForTesting
  bool isStopped = false;

  /// Halts sync activity. Cancels the stats-notification subscription,
  /// drains any pending requests in the queue (their callbacks are
  /// invoked with an error), removes all progress listeners, and
  /// causes future [sync] calls to become no-ops until [restart] is
  /// invoked. Idempotent — calling [stop] when already stopped is a
  /// no-op.
  Future<void> stop() async {
    if (isStopped) {
      _logger.info('stop() called, but service is already stopped. Ignoring.');
      return;
    }
    isStopped = true;
    _logger.info('Stopping sync service for $currentAtSign');

    _drainSyncQueue();

    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;

    _logger.finer('stopping stats notification subscription');
    try {
      await _statsNotificationSubscription?.cancel();
    } catch (e) {
      _logger.warning(
          'Error while cancelling stats notification subscription: $e');
    }

    removeAllProgressListeners();
  }

  /// Reverses a prior [stop]: re-subscribes to stats notifications and
  /// allows new [sync] calls to fire again. Progress listeners removed
  /// by [stop] are NOT restored — the caller must re-add them via
  /// [addProgressListener]. The sync queue starts empty after restart
  /// (it was drained on [stop]). Idempotent — calling [restart] when
  /// not stopped is a no-op.
  Future<void> start() async {
    if (!isStopped) {
      _logger.info('restart() called, but service is not stopped. Ignoring.');
      return;
    }
    _logger.info('Restarting sync service for $currentAtSign');
    isStopped = false;
    // Re-subscribe to stats notifications. Note that any sync run that
    // was in flight at the moment of stop() may still be on the call
    // stack; its `finally` will set _processInProgress / _syncInProgress
    // back to false on its own — restart() does not need to wait for
    // it. New sync() calls after restart will queue normally and fire
    // their microtask trigger as usual.
    await statsServiceListener();
    _startPeriodicSyncTimer();
  }

  void _drainSyncQueue() {
    // 1. Drain the sync request queue with errors
    final exception = AtClientException(
        error_codes['AtClientException'], 'SyncService has been stopped');

    while (syncRequests.isNotEmpty) {
      final request = syncRequests.removeFirst();
      request.result ??= SyncResult();
      request.result!
        ..syncStatus = SyncStatus.failure
        ..atClientException = exception;
      _safeInvokeOnError(request);
    }

    // 2. Notify progress listeners of the failure
    var progress = SyncProgress()
      ..atSign = currentAtSign
      ..syncStatus = SyncStatus.failure
      ..atClientException = exception
      ..message = 'SyncService stopped';

    for (var listener in _syncProgressListeners) {
      try {
        listener.onSyncProgressEvent(progress);
      } catch (e) {
        _logger.warning('Error notifying progress listener during stop: $e');
      }
    }
    _syncProgressListeners.clear();
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
    syncRequests.clear();
    _syncProgressListeners.clear();
  }

  int _parseToInteger(dynamic arg1) {
    if (arg1 is String) {
      return int.parse(arg1);
    }
    return arg1;
  }

  @visibleForTesting
  int getSyncRequestQueueSize() {
    return syncRequests.length;
  }
}

/// Per-entry breadcrumb threaded alongside [BatchRequest]s in
/// [_pushFromSyncQueue]. The wire response only carries the batch
/// `id`, but we need to know which atKey + op corresponds to that
/// id when handling per-entry success/failure (`removeFromSyncQueue`
/// / `KeyInfo` build). The [commitLogSeqNum] field lets the success
/// handler back-write the server-assigned commitId onto the
/// originating commit-log entry in O(1) (`getCommitEntry(seqNum)`)
/// instead of O(N log N) (full-log scan for the latest entry by
/// atKey). Nullable because tests + edge cases (skipCommit writes,
/// older queue entries persisted before the field was added) won't
/// have one — the slow path is the fallback in those cases.
class _BatchSource {
  final String atKey;
  final SyncQueueOp op;
  final int? commitLogSeqNum;

  const _BatchSource({
    required this.atKey,
    required this.op,
    this.commitLogSeqNum,
  });
}
