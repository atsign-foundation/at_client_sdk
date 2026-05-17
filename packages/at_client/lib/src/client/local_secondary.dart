// HiveKeystore.getExpiryKeysCache() is @visibleForTesting in the
// at_persistence package, but is the canonical access point we read
// here to surface nextExpiryAt / nextAvailableAt without duplicating
// the cache in this layer. The parallel persistence project will
// promote it to a public method on SecondaryKeyStore — at that point
// this file-level ignore goes away.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

// Private path: HiveKeystore isn't exported from the package barrel, but
// this file's `deleteExpiredKeys` needs the concrete class for the
// `is HiveKeystore` guard and the `getExpiredKeys()` call. The parallel
// persistence project will eventually expose these via a public method on
// SecondaryKeyStore at which point this private import goes away.
// ignore: implementation_imports
import 'package:at_persistence_secondary_server/src/keystore/hive_keystore.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

/// Contains methods to execute verb on local secondary storage using [executeVerb]
/// Set [AtClientPreference.isLocalStoreRequired] to true and other preferences that your app needs.
/// Delete and Update commands will be synced to the server
class LocalSecondary implements Secondary {
  final AtClient _atClient;

  late final AtSignLogger _logger;

  /// Local keystore used to store data for the current atSign.
  SecondaryKeyStore? keyStore;

  /// Sink for keystore-mutation events. Wired by [AtClientImpl] at
  /// construction to its [AtClientImpl.emitDataEvent]; left null by
  /// callers that don't need event propagation (most unit-test
  /// fixtures). Emits are silently dropped when null.
  final void Function(DataEvent)? _onEvent;

  void _emit(DataEvent e) => _onEvent?.call(e);

  /// Tracks the `availableAt` timestamp [_onAvailableFire] last
  /// emitted `DataUpdated` for, per key. Lets the available-timer
  /// sweep skip keys we've already fired for (the underlying record's
  /// `availableAt` is now in the past but unchanged). A subsequent
  /// `_update` that rewrites the record with a new future
  /// `availableAt` causes the cache's value to differ from this map's
  /// — the sweep then refires.
  ///
  /// In-memory only — does NOT survive process restart. Restart-side
  /// re-fire is acceptable: subscribers come up fresh and a single
  /// `DataUpdated` per restart is the consistent answer.
  final Map<String, DateTime> _firedAvailableAt = {};

  /// Pending client→server writes: a per-key dedup'd queue of atKey
  /// strings whose latest local write hasn't yet been pushed. Opened
  /// lazily on first use via [_ensureSyncQueueOpen]. Populated by
  /// [_update] / [_delete] and consumed by `SyncServiceImpl`. See
  /// `lib/src/sync/at_sync_queue.dart` for the queue's full contract.
  AtSyncQueue? _syncQueue;
  Future<AtSyncQueue>? _syncQueueOpenInflight;

  /// Tracks atKeys with a currently-executing [_update] / [_delete] —
  /// i.e. a write that has entered the keystore mutation phase but
  /// hasn't yet enqueued for sync. The sync service's pull-side
  /// conflict-detection consults [isWriteInProgress] alongside the
  /// sync queue, so a pull entry whose atKey matches an in-flight
  /// local write is treated as a conflict (skip apply, preserve the
  /// user's value).
  ///
  /// Without this, the window between [LocalSecondary]'s keystore op
  /// (which writes the new value to Hive) and its `_enqueueForSync`
  /// call (which appends to the sync queue) is unprotected — a pull
  /// firing in that window finds an empty queue, applies its entry,
  /// and silently overwrites the user's just-written value. The push
  /// path then reads the overwritten value and sends *that* to the
  /// server: the bug observed by `bypasscache_test`'s assertion that
  /// the updated value reaches the receiver.
  ///
  /// In-memory only — no Hive write per op. Per [LocalSecondary]
  /// instance.
  final Set<String> _writesInProgress = <String>{};

  /// True if a [_update] or [_delete] for [atKey] is currently
  /// executing on this LocalSecondary. Synchronous, cheap. Consulted
  /// by `SyncServiceImpl._syncFromServer` per pull entry.
  bool isWriteInProgress(String atKey) => _writesInProgress.contains(atKey);

  LocalSecondary(
    this._atClient, {
    this.keyStore,
    void Function(DataEvent)? onEvent,
  }) : _onEvent = onEvent {
    _logger = AtSignLogger('LocalSecondary (${_atClient.getCurrentAtSign()})');
    keyStore ??= SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(_atClient.getCurrentAtSign())!
        .getSecondaryKeyStore();
  }

  /// Idempotent lazy-open of the sync queue. The first caller wins
  /// the open; concurrent callers await the same in-flight future so
  /// we never call `Hive.openBox` twice for the same atSign.
  ///
  /// Must run AFTER the at_persistence_secondary_server's
  /// `HivePersistenceManager.init(storagePath)` has called
  /// `Hive.init(...)`, which is guaranteed by the
  /// [StorageManager._initStorage] call ordering during AtClient
  /// init. We intentionally do not call `Hive.init` here — rerunning
  /// it with a different path would silently misroute the box.
  Future<AtSyncQueue> _ensureSyncQueueOpen() {
    final existing = _syncQueue;
    if (existing != null) return Future.value(existing);
    return _syncQueueOpenInflight ??= () async {
      final atSign = _atClient.getCurrentAtSign();
      if (atSign == null) {
        throw StateError(
          'LocalSecondary.syncQueue accessed before currentAtSign was '
          'set; AtClientManager.setCurrentAtSign must run first',
        );
      }
      final q = AtSyncQueue(atSign: atSign);
      await q.open();
      _syncQueue = q;
      return q;
    }();
  }

  /// Number of atKeys with pending client→server writes. Reads the
  /// in-memory queue length (no Hive I/O). Triggers a one-time
  /// open of the queue on first call.
  Future<int> get syncQueueSize async {
    final q = await _ensureSyncQueueOpen();
    return q.size;
  }

  /// Synchronous, side-effect-free snapshot of the current queue
  /// size. Returns `null` when the queue hasn't been opened yet
  /// (the caller hasn't done any sync-eligible writes). Used by
  /// `SyncServiceImpl._informSyncProgress` to attach
  /// `pendingPushCount` to events without awaiting (which would
  /// change the relative ordering of progress emission and the
  /// sync round it describes). Production callers that don't mind
  /// the lazy-open should use [syncQueueSize] instead.
  int? get syncQueueSyncSnapshot => _syncQueue?.size;

  /// Returns up to [limit] atKey strings from the front of the
  /// pending-write queue in FIFO order. Does NOT remove them; the
  /// caller is expected to call [removeFromSyncQueue] per atKey
  /// after a successful push.
  Future<List<String>> peekSyncQueue({int? limit}) async {
    final q = await _ensureSyncQueueOpen();
    return q.peek(limit: limit);
  }

  /// Reads the persisted record (op + ts) for [atKey], or null if
  /// no record exists. Used by `SyncServiceImpl` when building the
  /// outgoing batch — the atKey itself comes from [peekSyncQueue],
  /// the op tells us whether to build update / delete / etc.
  Future<SyncQueueEntry?> readSyncQueueEntry(String atKey) async {
    final q = await _ensureSyncQueueOpen();
    return q.readEntry(atKey);
  }

  /// Removes [atKey] from both the in-memory queue and the persisted
  /// box. Called after a successful server-side push, OR when a
  /// drain attempt finds the underlying keystore value missing
  /// (race-tolerated removal: a queue write may have committed
  /// without the keystore write landing, e.g. across a crash).
  Future<void> removeFromSyncQueue(String atKey) async {
    final q = await _ensureSyncQueueOpen();
    await q.remove(atKey);
  }

  /// Test seam — production code goes through the public API above.
  /// Direct access to the queue lets tests inject pre-populated
  /// state, assert on persistence-layer behaviour, or close the
  /// queue without tearing down the whole LocalSecondary.
  @visibleForTesting
  Future<AtSyncQueue> get syncQueueForTest => _ensureSyncQueueOpen();

  /// Predicate: should a write to [atKey] (with operation [op]) be
  /// enqueued for client→server sync? Returns true for self / shared
  /// / public / reserved keys (the last covers
  /// `publickey.<sharedWith>@me` and `shared_key.<sharedWith>@me`
  /// which the encryption layer needs to reach the recipient).
  ///
  /// Returns false for local keys (`local:` prefix) and invalid keys
  /// (defensive).
  ///
  /// **`cached:` keys, special case for delete:** cached-shared /
  /// cached-public keys are normally created by the pull path
  /// (`_pullToLocal`, with `cameFromServer: true`), so a put-side
  /// enqueue is suppressed by the `cameFromServer` gate before we
  /// reach this predicate. But a *receiver-initiated delete* of a
  /// cached key is genuinely client→server: the user wants the
  /// server to drop its cached copy. Allow `delete` ops on
  /// `cached:` keys to flow through; everything else on `cached:`
  /// stays filtered (rare and ambiguous — the server typically
  /// owns cached-key writes).
  ///
  /// Visible for testing so the predicate's semantics can be locked
  /// down independently of the enqueue flow.
  ///
  /// **Why we check `cached:` as a string prefix first** instead of
  /// relying solely on `AtKey.getKeyType`: the regex-based classifier
  /// in at_commons checks `reservedKey` via `isPartialMatch`, which
  /// returns true for any input that *contains* a reserved-key
  /// substring. `cached:public:publickey@<atSign>` contains
  /// `publickey@<atSign>` (a reserved key) and is therefore
  /// misclassified as `KeyType.reservedKey` rather than
  /// `KeyType.cachedPublicKey`. Without the prefix check, that
  /// misclassification lets cached encryption-public-key writes
  /// (from `AbstractAtKeyEncryption._getSharedWithPublicKey`'s local
  /// cache write) flow into the sync queue, where the server then
  /// rejects them with `AT0003 Invalid syntax` and the no-progress
  /// guard burns retries forever.
  @visibleForTesting
  static bool shouldEnqueueForSync(String atKey, SyncQueueOp op) {
    if (atKey.startsWith('cached:')) {
      // Receiver-initiated delete of a cached key is the one
      // legitimate client→server case for cached:; everything else
      // (puts, meta updates) is server-originated and shouldn't be
      // pushed back.
      return op == SyncQueueOp.delete;
    }
    final type = AtKey.getKeyType(atKey);
    return type == KeyType.selfKey ||
        type == KeyType.sharedKey ||
        type == KeyType.publicKey ||
        type == KeyType.reservedKey;
  }

  /// Enqueues [atKey] for client→server sync with operation [op] and
  /// triggers the sync service to drain. Called from [_update] /
  /// [_delete] AFTER the real keystore operation succeeds. Skips
  /// enqueuing when the write is a server replay
  /// ([cameFromServer] true) or when the key isn't sync-eligible
  /// per [shouldEnqueueForSync].
  ///
  /// **Orphaned commit-log entry handling:** when a queue entry for
  /// the same [atKey] already exists (UPDATE→UPDATE, UPDATE→DELETE,
  /// etc.), the prior keystore op's commit-log entry will never be
  /// pushed — queue dedup means only the newer op makes it to the
  /// server. We delete that prior commit-log entry by its seqNum
  /// here so it doesn't sit forever with a null commitId, which
  /// would skip the back-write, fail commit-log compaction's
  /// `removeWhere(commitId == null)` filter, and leak in the log
  /// indefinitely.
  Future<void> _enqueueForSync(
    String atKey,
    SyncQueueOp op, {
    required bool cameFromServer,
    int? commitLogSeqNum,
  }) async {
    if (cameFromServer) return;
    if (!shouldEnqueueForSync(atKey, op)) return;
    try {
      final q = await _ensureSyncQueueOpen();
      final prior = q.readEntry(atKey);
      if (prior != null && prior.commitLogSeqNum != null) {
        await _removeOrphanedCommitLogEntry(prior.commitLogSeqNum!);
      }
      await q.enqueue(atKey, op, commitLogSeqNum: commitLogSeqNum);
      // Trigger SyncServiceImpl to drain. Today this enqueues a
      // sync request via the existing request-coalescing layer
      // (`_addSyncRequestToQueue` → microtask → `processSyncRequests`).
      // The sync service then peeks our queue and pushes batches.
      _atClient.syncService.sync();
    } catch (e, st) {
      // Failing to enqueue is a serious correctness problem (the
      // write WILL eventually be picked up by the periodic 30s
      // safety-net timer if the queue's box becomes accessible
      // again, but the immediate sync trigger is gone). Log loudly.
      _logger.shout('failed to enqueue $atKey for sync: $e\n$st');
    }
  }

  /// Removes the commit-log entry at [seqNum]. Called when a queue
  /// re-enqueue supersedes an earlier op for the same atKey, leaving
  /// the earlier op's commit-log entry orphaned. Best-effort —
  /// failures here would just leave a null-commitId entry behind,
  /// which is undesirable (compaction skips it) but not corrupting.
  Future<void> _removeOrphanedCommitLogEntry(int seqNum) async {
    try {
      final atSign = _atClient.getCurrentAtSign();
      if (atSign == null) return;
      final atCommitLog =
          await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);
      if (atCommitLog == null) return;
      await atCommitLog.commitLogKeyStore.remove(seqNum);
    } on Exception catch (e) {
      _logger.warning('failed to remove orphaned commit-log entry $seqNum: $e');
    }
  }

  // temporarily cache enrollmentDetails until we store in local secondary
  @visibleForTesting
  Enrollment? enrollment;

  /// Executes a verb builder on the local secondary.
  ///
  /// The [sync] parameter is retained for back-compat with the
  /// `Secondary` interface and is ignored: `_update` / `_delete`
  /// enqueue into the client→server sync queue themselves whenever
  /// the key is sync-eligible and [cameFromServer] is false.
  ///
  /// When [cameFromServer] is true the caller is replaying a
  /// server-originated change into local storage (today only
  /// `SyncServiceImpl._pullToLocal` does this). The flag tells
  /// `_update` / `_delete` to skip the sync-queue enqueue — the
  /// server already has the entry; bouncing it back would be a
  /// loop.
  @override
  Future<String?> executeVerb(VerbBuilder builder,
      {bool? sync, bool cameFromServer = false}) async {
    String? verbResult;

    try {
      if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
        if (builder is UpdateVerbBuilder) {
          verbResult = await _update(builder, cameFromServer: cameFromServer);
        } else if (builder is DeleteVerbBuilder) {
          verbResult = await _delete(builder, cameFromServer: cameFromServer);
        }
      } else if (builder is LLookupVerbBuilder) {
        verbResult = await _llookup(builder);
      } else if (builder is ScanVerbBuilder) {
        verbResult = await _scan(builder);
      }
    } on AtLookUpException catch (e) {
      // Catches AtLookupException and
      // converts to AtClientException. rethrows any other exception.
      throw (AtClientException(e.errorCode, e.errorMessage));
    }
    return verbResult;
  }

  Future<String> _update(UpdateVerbBuilder builder,
      {bool cameFromServer = false}) async {
    final updateKey = builder.buildKey();
    // Mark this key as having a write in progress so the sync pull's
    // conflict-detection (in `SyncServiceImpl._syncFromServer`) skips
    // any server entry for the same atKey that arrives during the
    // window between keystore op and queue enqueue. cameFromServer
    // writes are server-applied (no race possible with our own queue).
    if (!cameFromServer) _writesInProgress.add(updateKey);
    try {
      dynamic updateResult;
      if (!await isEnrollmentAuthorizedForOperation(updateKey, builder)) {
        throw UnAuthorizedException(
            'Cannot perform update on $updateKey due to insufficient privilege');
      }

      // Defensive code. Somewhere, something is turning a ttb == null into a
      // ttb == 0. The result of this is that availableAt is being set. This is
      // no particular biggie except it's annoying. It does also consume
      // storage.
      // TODO Track this down; it's either in atServer receiving from another
      // one, or it's when it's receiving from client, or the client is
      // inventing it. My guess is it's when the first atServer is receiving
      // the request from the client.
      if (builder.atKey.metadata.ttb == 0) {
        builder.atKey.metadata.ttb = null;
      }
      // Probe previous metadata BEFORE the write so we can compute
      // visibility transitions for event emission. May throw
      // KeyNotFoundException for first-write — treat as "no previous".
      // The cross-tier safety property here: this LocalSecondary is the
      // only in-process emit point for keystore-mutation events. The
      // notification path from the remote atServer comes through a
      // separate channel (NotificationServiceImpl) and already carries
      // availableAt in the envelope.
      AtMetaData? prevMeta;
      try {
        prevMeta = await keyStore!.getMeta(updateKey);
      } on Exception {
        prevMeta = null;
      }
      final now = DateTime.timestamp();
      final bool? prevVisible =
          prevMeta == null ? null : _visibleAt(prevMeta.availableAt, now);

      late AtMetaData emittedMetadata;
      // Track which op variant we performed so we can record the
      // matching `SyncQueueOp` after the keystore op succeeds.
      late SyncQueueOp syncQueueOp;
      switch (builder.operation) {
        case AtConstants.updateMeta:
          var atMetadata = AtMetaData.fromCommonsMetadata(
            builder.atKey.metadata,
            _atClient.getCurrentAtSign()!,
          );
          updateResult = await keyStore!.putMeta(updateKey, atMetadata);
          emittedMetadata = atMetadata;
          syncQueueOp = SyncQueueOp.updateMeta;
          break;
        default:
          var atData = AtData();
          atData.data = builder.value;
          var atMetadata = AtMetaData.fromCommonsMetadata(
            builder.atKey.metadata,
            _atClient.getCurrentAtSign()!,
          );

          if (_logger.isLoggable('finest')) {
            _logger.finest('Before keyStore.putAll'
                ' $updateKey'
                ' cameFromServer: $cameFromServer'
                ' ttl ${atMetadata.ttl}'
                ' expiresAt ${atMetadata.expiresAt}'
                ' ttb ${atMetadata.ttb}'
                ' availableAt ${atMetadata.availableAt}'
                '');
          }

          updateResult = await keyStore!.putAll(updateKey, atData, atMetadata);

          if (_logger.isLoggable('finest')) {
            final AtData fetchedBack = await keyStore!.get(updateKey);
            _logger.finest('After keyStore.get fetched back'
                ' $updateKey'
                ' cameFromServer: $cameFromServer'
                ' ttl ${fetchedBack.metaData?.ttl}'
                ' expiresAt ${fetchedBack.metaData?.expiresAt}'
                ' ttb ${fetchedBack.metaData?.ttb}'
                ' availableAt ${fetchedBack.metaData?.availableAt}'
                '');
          }

          emittedMetadata = atMetadata;
          syncQueueOp = SyncQueueOp.updateAll;
          break;
      }
      // Enqueue for client→server sync after the keystore write
      // succeeded (so the queue never points at a missing record
      // for normal writes). `_enqueueForSync` is a no-op when
      // [cameFromServer] is true or the key isn't sync-eligible.
      // The keystore op's return value IS the commit-log sequence
      // number (`Future<int?>` from putAll/putMeta); thread it
      // through so the push path can do an O(1) commit-log lookup
      // for the back-write of the server-assigned commitId.
      await _enqueueForSync(
        updateKey,
        syncQueueOp,
        cameFromServer: cameFromServer,
        commitLogSeqNum: updateResult is int ? updateResult : null,
      );

      final newVisible = _visibleAt(emittedMetadata.availableAt, now);
      if (newVisible) {
        _emit(DataUpdated(builder.atKey, metadata: emittedMetadata));
        // If the record carries an availableAt (necessarily in the
        // past since newVisible is true), record it so the
        // available-timer sweep won't re-emit DataUpdated for the
        // same crossing.
        final avail = emittedMetadata.availableAt;
        if (avail != null) {
          _firedAvailableAt[updateKey] = avail;
        } else {
          _firedAvailableAt.remove(updateKey);
        }
      } else if (prevVisible == true) {
        // visible → not-yet: record dropped out of listeners' view.
        // Clear any prior fire record — when the new future
        // availableAt crosses, the timer should fire DataUpdated.
        _emit(DataDeleted(builder.atKey));
        _firedAvailableAt.remove(updateKey);
      } else {
        // Silent (fresh future-write or future→future re-write).
        // The new availableAt differs from any previously fired
        // value, so let the sweep evaluate normally — clear any
        // stale fire record.
        _firedAvailableAt.remove(updateKey);
      }

      return 'data:$updateResult';
    } on DataStoreException catch (e) {
      _logger.severe('exception in local update:${e.toString()}');
      rethrow;
    } finally {
      if (!cameFromServer) _writesInProgress.remove(updateKey);
    }
  }

  Future<String> _llookup(LLookupVerbBuilder builder) async {
    var llookupKey = '';
    try {
      llookupKey = builder.buildKey();
      if (!await isEnrollmentAuthorizedForOperation(llookupKey, builder)) {
        throw UnAuthorizedException(
            'Cannot perform llookup on $llookupKey due to insufficient privilege');
      }
      var llookupMeta = await keyStore!.getMeta(llookupKey);
      var isActive = _isActiveKey(llookupMeta);
      String? result;
      if (isActive) {
        var llookupResult = await keyStore!.get(llookupKey);
        result = _prepareResponseData(builder.operation, llookupResult);
      }
      return 'data:$result';
    } on DataStoreException catch (e) {
      _logger.severe('exception in llookup:${e.toString()}');
      rethrow;
    } on KeyNotFoundException catch (e) {
      e.stack(AtChainedException(
          Intent.fetchData, ExceptionScenario.keyNotFound, e.message));
      rethrow;
    }
  }

  Future<String> _delete(DeleteVerbBuilder builder,
      {bool cameFromServer = false, bool localOnly = false}) async {
    var deleteKey = builder.buildKey();
    if (!await isEnrollmentAuthorizedForOperation(deleteKey, builder)) {
      throw UnAuthorizedException(
          'Cannot perform delete on $deleteKey due to insufficient privilege');
    }
    // Same pull-race protection as _update — a server entry for the
    // same atKey arriving during the keystore-op-to-enqueue window
    // would otherwise overwrite our pending delete with the prior
    // server value (then push pushes back the wrong op).
    if (!cameFromServer && !localOnly) _writesInProgress.add(deleteKey);
    try {
      var deleteResult = await keyStore!.remove(deleteKey);
      // `wasExpired` mirrors `localOnly` here — the only caller that
      // sets `localOnly: true` is the expiry sweep (see
      // [deleteExpiredKeys]). Tagging the DataDeleted event lets
      // downstream listeners (notably AtCollection's parent-delete
      // cascade) distinguish autonomous TTL cleanup from
      // user-initiated deletes and skip redundant work for the
      // former.
      _emit(DataDeleted(builder.atKey, wasExpired: localOnly));
      _firedAvailableAt.remove(deleteKey);
      // Enqueue for client→server sync after the keystore op
      // succeeded — UNLESS this is a local-only deletion that
      // doesn't need to propagate. Two suppression paths:
      //
      // - `cameFromServer: true` — the delete was replayed from
      //   the server (`_pullToLocal`), no point bouncing it back.
      // - `localOnly: true` — TTL-driven local cleanup. Both ends
      //   of an Atsign Protocol key relationship expire keys
      //   independently from their own metadata; the publisher's
      //   atServer drops the original at TTL, the receiver's
      //   atServer drops its `cached:` copy at the same TTL. No
      //   client→server tell needed.
      //
      // For caller-initiated deletes (the default both-flags-false
      // case) we DO enqueue, even if the key never existed locally
      // (`deleteResult` may be whatever `remove` returns for a
      // missing key) — the user's intent is "make sure it's gone
      // everywhere", and a delete for a never-synced record costs
      // only a commitId++ server-side.
      //
      // `keyStore.remove` returns `Future<int?>` — the commit-log
      // sequence number; thread it through so the push path can do
      // an O(1) commit-log lookup for the back-write.
      if (!localOnly) {
        await _enqueueForSync(
          deleteKey,
          SyncQueueOp.delete,
          cameFromServer: cameFromServer,
          commitLogSeqNum: deleteResult,
        );
      }
      return 'data:$deleteResult';
    } on DataStoreException catch (e) {
      _logger.severe('exception in delete:${e.toString()}');
      rethrow;
    } finally {
      if (!cameFromServer && !localOnly) _writesInProgress.remove(deleteKey);
    }
  }

  /// Deletes every key currently flagged expired by the underlying
  /// [HiveKeystore]'s in-memory cache. Each deletion goes through
  /// [_delete], which fires a [DataDeleted] on [AtClient.dataEvents]
  /// — so subscribers see expirations the same way they see any other
  /// delete. Returns the number of keys removed.
  ///
  /// Callers arming a timer via [AtClient.dataEvents] should suppress
  /// re-arms while a sweep is in flight (the events fired during this
  /// method would otherwise cause N redundant re-arms).
  /// [AtClientImpl._onExpiryFire] does this via a `_sweepInFlight`
  /// flag.
  ///
  /// Returns 0 (no-op) when the underlying keystore is not a
  /// [HiveKeystore]; non-Hive keystores are responsible for their own
  /// expiry mechanism if any.
  Future<int> deleteExpiredKeys() async {
    final ks = keyStore;
    if (ks is! HiveKeystore) {
      _logger.shout('Underlying keyStore is not HiveKeystore');
      return 0;
    }
    final expired = await ks.getExpiredKeys();
    if (expired.isEmpty) return 0;
    var deleted = 0;
    for (final keyString in expired) {
      try {
        final atKey = AtKey.fromString(keyString);
        final builder = DeleteVerbBuilder()..atKey = atKey;
        _logger.finer('Deleting expired key $atKey');
        // localOnly: true — TTL expiry happens autonomously at every
        // tier of the Atsign Protocol (publisher atServer, receiver
        // atServer, every atClient). No client→server push needed;
        // the publisher's atServer has already dropped (or will drop)
        // its own copy at the same TTL, and is responsible for the
        // recipients' `cached:` evictions.
        await _delete(builder, localOnly: true);
        deleted++;
      } on Exception catch (e) {
        _logger.warning('expiry sweep failed for $keyString: $e');
      }
    }
    return deleted;
  }

  Future<String?> _scan(ScanVerbBuilder builder) async {
    try {
      // Call to remote secondary sever and performs an outbound scan to retrieve values from sharedBy secondary
      // shared with current atSign
      if (builder.sharedBy != null) {
        var command = builder.buildCommand();
        return _atClient
            .getRemoteSecondary()!
            .executeCommand(command, auth: true);
      }
      List<String?> keys;
      keys = keyStore!.getKeys(regex: builder.regex) as List<String?>;
      // Gets keys shared to sharedWith atSign.
      if (builder.sharedWith != null) {
        keys.retainWhere(
            (element) => element!.startsWith(builder.sharedWith!) == true);
      }
      keys.removeWhere((key) => _shouldHideKeys(key!, builder.showHiddenKeys));
      final keysToRemove = <String>[];
      await Future.forEach(keys, (key) async {
        if (!(await isEnrollmentAuthorizedForOperation(
            key.toString(), builder))) {
          keysToRemove.add(key.toString());
        }
      });
      keys.removeWhere((key) => keysToRemove.contains(key));
      var keyString = keys.toString();
      // Apply regex on keyString to remove unnecessary characters and spaces
      keyString = keyString.replaceFirst(RegExp(r'^\['), '');
      keyString = keyString.replaceFirst(RegExp(r'\]$'), '');
      keyString = keyString.replaceAll(', ', ',');
      var keysArray = keyString.isNotEmpty ? (keyString.split(',')) : [];
      return json.encode(keysArray);
    } on DataStoreException catch (e) {
      _logger.severe('exception in scan:${e.toString()}');
      rethrow;
    }
  }

  bool _shouldHideKeys(String key, bool showHiddenKeys) {
    // If showHidden is set to true, display hidden public keys.
    // So returning false
    if ((key.toString().startsWith('public:__') || key.startsWith('_')) &&
        showHiddenKeys) {
      return false;
    }
    // Do not display keys that starts with 'private:' or 'privatekey:' or public:_
    return key.toString().startsWith('private:') ||
        key.toString().startsWith('privatekey:') ||
        key.toString().startsWith('public:_') ||
        key.startsWith('_');
  }

  /// Verifies if the key is active, If key is active, return true; else false.
  bool _isActiveKey(AtMetaData? atMetaData) {
    // The legacy keys will not have metadata.
    // Returning true if metadata is null
    if (atMetaData == null) return true;
    var ttb = atMetaData.availableAt;
    var ttl = atMetaData.expiresAt;
    if (ttb == null && ttl == null) return true;
    var now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (ttb != null) {
      var ttbMs = ttb.toUtc().millisecondsSinceEpoch;
      if (ttbMs > now) return false;
    }
    if (ttl != null) {
      var ttlMs = ttl.toUtc().millisecondsSinceEpoch;
      if (ttlMs < now) return false;
    }
    //If TTB or TTL populated but not met, return true.
    return true;
  }

  /// Visibility predicate for event-emission decisions: a record
  /// with this `availableAt` is considered visible at [at]. Mirrors
  /// the `availableAt` arm of [_isActiveKey] but excludes the
  /// `expiresAt` arm — visibility for emit purposes is independent
  /// of expiry (an already-expired record's `_update` should still
  /// emit normally; the expiry timer fires `DataDeleted` on its own
  /// schedule).
  bool _visibleAt(DateTime? availableAt, DateTime at) {
    if (availableAt == null) return true;
    return availableAt.toUtc().millisecondsSinceEpoch <=
        at.toUtc().millisecondsSinceEpoch;
  }

  /// Earliest pending `expiresAt` across keys with TTL, or `null`
  /// if none. Reads from the underlying [HiveKeystore]'s
  /// `_expiryKeysCache` — which is rebuilt on keystore open and
  /// maintained on every put. O(n) over the cache size; n is the
  /// count of keys with TTL or TTB set, NOT the total record count.
  ///
  /// Returns `null` when the keystore isn't a [HiveKeystore]
  /// (non-Hive backends are responsible for their own timer
  /// surfaces).
  DateTime? nextExpiryAt() {
    final ks = keyStore;
    if (ks is! HiveKeystore) return null;
    DateTime? earliest;
    for (final entry in ks.getExpiryKeysCache().values) {
      final exp = entry['expiresAt'];
      if (exp == null) continue;
      if (earliest == null || exp.isBefore(earliest)) earliest = exp;
    }
    return earliest;
  }

  /// Earliest pending `availableAt` across keys with TTB, excluding
  /// keys whose current `availableAt` matches a previously fired
  /// timestamp ([_firedAvailableAt]). Returns `null` if none.
  DateTime? nextAvailableAt() {
    final ks = keyStore;
    if (ks is! HiveKeystore) return null;
    DateTime? earliest;
    for (final entry in ks.getExpiryKeysCache().entries) {
      final avail = entry.value['availableAt'];
      if (avail == null) continue;
      final fired = _firedAvailableAt[entry.key];
      if (fired != null && fired.isAtSameMomentAs(avail)) continue;
      if (earliest == null || avail.isBefore(earliest)) earliest = avail;
    }
    return earliest;
  }

  /// Yields every key with `availableAt <= cutoff` whose current
  /// `availableAt` doesn't match a previously fired timestamp. Used
  /// by [AtClientImpl._onAvailableFire] to drive the visibility-
  /// onset sweep.
  ///
  /// Iteration order is unspecified — the underlying cache is a
  /// `HashMap`. Snapshots before yielding so concurrent writes
  /// during the sweep don't perturb the walk.
  Iterable<String> keysWithAvailableAtAtOrBefore(DateTime cutoff) sync* {
    final ks = keyStore;
    if (ks is! HiveKeystore) return;
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final snapshot = List<MapEntry<String, Map<String, DateTime?>>>.from(
        ks.getExpiryKeysCache().entries);
    for (final entry in snapshot) {
      final avail = entry.value['availableAt'];
      if (avail == null) continue;
      if (avail.toUtc().millisecondsSinceEpoch > cutoffMs) continue;
      final fired = _firedAvailableAt[entry.key];
      if (fired != null && fired.isAtSameMomentAs(avail)) continue;
      yield entry.key;
    }
  }

  /// Records that the available-timer sweep just emitted
  /// `DataUpdated` for [key], so subsequent sweeps don't re-fire
  /// for the same `availableAt` crossing. A subsequent `_update`
  /// that rewrites the record with a new future `availableAt`
  /// (different from the recorded one) re-enables firing.
  void dropAvailabilityCacheEntry(String key) {
    final ks = keyStore;
    if (ks is! HiveKeystore) return;
    final entry = ks.getExpiryKeysCache()[key];
    final avail = entry?['availableAt'];
    if (avail != null) {
      _firedAvailableAt[key] = avail;
    }
  }

  /// Pre-marks every key whose `availableAt` is at or before [now] as
  /// "already fired" in the in-memory [_firedAvailableAt] map. The
  /// availability sweep ([AtClientImpl._onAvailableFire]) checks this
  /// map and skips matching entries, so this prevents the sweep from
  /// replaying historical `availableAt` crossings on every process
  /// start.
  ///
  /// Without this seeding, a freshly-started AtClient with a populated
  /// local hive (e.g. a subscriber restarted with the same
  /// `--storage-dir` while cached entries from a prior publisher
  /// session are still alive) would emit a [DataUpdated] for every
  /// such entry — and AtCollection would forward those as
  /// [CSubItemUpdated] / [CItemUpdated], so consumer listeners would
  /// see what looks like a fresh stream of arrivals when nothing new
  /// has actually been written.
  ///
  /// The seed is unconditional: any key with a past `availableAt` is
  /// treated as already-fired on this process. New writes that arrive
  /// AFTER seeding go through `_update`, which fires DataUpdated
  /// itself (and records its own `_firedAvailableAt` entry) — so this
  /// only suppresses HISTORICAL replay, not fresh emissions.
  void seedAvailabilityFiredAsOf(DateTime now) {
    final ks = keyStore;
    if (ks is! HiveKeystore) return;
    final cutoffMs = now.toUtc().millisecondsSinceEpoch;
    for (final entry in ks.getExpiryKeysCache().entries) {
      final avail = entry.value['availableAt'];
      if (avail == null) continue;
      if (avail.toUtc().millisecondsSinceEpoch > cutoffMs) continue;
      _firedAvailableAt[entry.key] = avail;
    }
  }

  String? _prepareResponseData(String? operation, AtData? atData) {
    String? result;
    if (atData == null) {
      return result;
    }
    switch (operation) {
      case 'meta':
        result = json.encode(atData.metaData!.toJson());
        break;
      case 'all':
        result = json.encode(atData.toJson());
        break;
      default:
        result = atData.data;
        break;
    }
    return result;
  }

  @Deprecated("Use getPkamPrivateKey")
  Future<String?> getPrivateKey() => getPkamPrivateKey();

  AtChopsKeys? get atChopsKeys => _atClient.atChops?.atChopsKeys;

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getPkamPrivateKey() async {
    String? v = atChopsKeys?.atPkamKeyPair?.atPrivateKey.privateKey;
    v ??= (await keyStore!.get(AtConstants.atPkamPrivateKey))?.data;
    return v;
  }

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getEncryptionPrivateKey() async {
    String? v = atChopsKeys?.atEncryptionKeyPair?.atPrivateKey.privateKey;
    v ??= (await keyStore!.get(AtConstants.atEncryptionPrivateKey))?.data;
    return v;
  }

  @Deprecated("Use getPkamPublicKey")
  Future<String?> getPublicKey() => getPkamPublicKey();

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getPkamPublicKey() async {
    String? v = atChopsKeys?.atPkamKeyPair?.atPublicKey.publicKey;
    v ??= (await keyStore!.get(AtConstants.atPkamPublicKey))?.data;
    return v;
  }

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getEncryptionPublicKey(String atSign) async {
    atSign = AtUtils.fixAtSign(atSign);
    String? v = atChopsKeys?.atEncryptionKeyPair?.atPublicKey.publicKey;
    v ??= (await keyStore!.get('${AtConstants.atEncryptionPublicKey}$atSign'))
        ?.data;

    return v;
  }

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getEncryptionSelfKey() async {
    String? v = atChopsKeys?.selfEncryptionKey?.key;
    v ??= (await keyStore!.get(AtConstants.atEncryptionSelfKey))?.data;
    return v;
  }

  /// Returns `true` on successfully storing the values into local secondary.
  Future<bool> putValue(String key, String value) async {
    dynamic isStored;
    var atData = AtData()..data = value;
    isStored = await keyStore!.put(key, atData);
    return isStored != null ? true : false;
  }

  Future<bool> isEnrollmentAuthorizedForOperation(
      String key, VerbBuilder verbBuilder) async {
    // Do whatever you want with "local" keys
    if (key.startsWith('local:')) {
      return true;
    }
    // if there is no enrollment, return true
    enrollment ??= await _getEnrollmentDetails();
    if (_atClient.enrollmentId == null ||
        enrollment == null ||
        _shouldSkipKeyFromEnrollmentAuthorization(key)) {
      _logger.finest('Skipping enrollment authorization check for key: $key');
      return true;
    }
    final enrollNamespaces = enrollment!.namespace;
    var keyNamespace = AtKey.fromString(key).namespace;
    _logger.finest(
        'Checking for enrollment authorization for key: $key with enrollmentId : ${_atClient.enrollmentId} for namespace: $keyNamespace');
    // * denotes access to all namespaces.
    final access = enrollNamespaces!.containsKey('*')
        ? enrollNamespaces['*']
        : enrollNamespaces[keyNamespace];

    if (access == null) {
      _logger.finer(
          'Access permissions not found for the enrollment id: ${_atClient.enrollmentId}. Not authorized for the operation');
      return false;
    }
    if (keyNamespace == null && enrollNamespaces.containsKey('*')) {
      _logger.finer(
          'Access permissions for the the enrollment id: ${_atClient.enrollmentId} : $access for namespace: $keyNamespace');
      if (_isReadAllowed(verbBuilder, access) ||
          _isWriteAllowed(verbBuilder, access)) {
        _logger.finest(
            'Enrollment id: ${_atClient.enrollmentId} : $access for namespace: $keyNamespace is authorized to perform operation');
        return true;
      }
      _logger.finest(
          'Enrollment id: ${_atClient.enrollmentId} : $access for namespace: $keyNamespace is not authorized to perform operation');
      return false;
    }
    return _isReadAllowed(verbBuilder, access) ||
        _isWriteAllowed(verbBuilder, access);
  }

  Future<Enrollment?> _getEnrollmentDetails() async {
    if (_atClient.enrollmentId == null) {
      return null;
    }

    // Fetch enrollment information from local secondary
    AtData? enrollmentInfoFromLocalSecondary;
    try {
      enrollmentInfoFromLocalSecondary = await keyStore?.get(
          'local:${_atClient.enrollmentId}${_atClient.getCurrentAtSign()}');
    } on Exception {
      _logger.finer(
          'Enrollment information for id: ${_atClient.enrollmentId} not found in local secondary. Fetching from server');
    }

    // If enrollmentInfo is not found in local secondary, fetch the info from the remote secondary server and cache it in local
    // secondary.
    String? enrollmentInfoFromServer;
    if (enrollmentInfoFromLocalSecondary == null) {
      try {
        enrollmentInfoFromServer = await _atClient
            .getRemoteSecondary()
            ?.executeCommand(
                'enroll:fetch:{"enrollmentId":"${_atClient.enrollmentId}"}\n',
                auth: true);
      } on AtException catch (e) {
        _logger.finer(
            'Failed to fetch enrollment information for id: ${_atClient.enrollmentId} from server caused by ${e.toString()}');
      } on AtLookUpException catch (e) {
        _logger.finer(
            'Failed to fetch enrollment information for id: ${_atClient.enrollmentId} from server caused by ${e.toString()}');
      }
      enrollmentInfoFromServer =
          enrollmentInfoFromServer?.replaceFirst(RegExp('^data:'), '');
      Map enrollmentDetailsMap = jsonDecode(enrollmentInfoFromServer!);
      _logger.info('Enrollment Details Map : $enrollmentDetailsMap');
      enrollment = Enrollment()
        ..appName = enrollmentDetailsMap['appName']
        ..deviceName = enrollmentDetailsMap['deviceName']
        ..namespace = enrollmentDetailsMap['namespace']
        ..encryptedAPKAMSymmetricKey =
            enrollmentDetailsMap['encryptedAPKAMSymmetricKey'];

      AtData atData = AtData()..data = jsonEncode(enrollment);
      // The enrollment data is fetch from server, Set skipCommit to true to prevent
      // the key sync back to server
      await keyStore?.put(
          '${_atClient.enrollmentId}.new.enrollments.__manage${_atClient.getCurrentAtSign()}',
          atData,
          skipCommit: true);
    } else {
      enrollment = Enrollment.fromJSON(
          jsonDecode(enrollmentInfoFromLocalSecondary.data!));
    }

    if (enrollment == null) {
      throw AtKeyNotFoundException(
          'Enrollment key for enrollmentId: ${_atClient.enrollmentId} not found in server');
    }
    return enrollment!;
  }

  bool _isReadAllowed(VerbBuilder verbBuilder, String access) {
    return (verbBuilder is LLookupVerbBuilder ||
            verbBuilder is LookupVerbBuilder ||
            verbBuilder is ScanVerbBuilder) &&
        (access == 'r' || access == 'rw');
  }

  bool _isWriteAllowed(VerbBuilder verbBuilder, String access) {
    return (verbBuilder is UpdateVerbBuilder ||
            verbBuilder is DeleteVerbBuilder ||
            verbBuilder is NotifyVerbBuilder ||
            verbBuilder is NotifyAllVerbBuilder ||
            verbBuilder is NotifyRemoveVerbBuilder) &&
        access == 'rw';
  }

  /// The enrollment authorization check does not include the following KeyTypes.
  /// Therefore, return true to skip the authorization check.
  /// This applies to Reserved keys, Cached shared keys, Cached public keys, and local keys
  bool _shouldSkipKeyFromEnrollmentAuthorization(String? atKey) {
    if (atKey == null) {
      return false;
    }
    KeyType keyType = AtKey.getKeyType(atKey);
    return (keyType == KeyType.reservedKey ||
        keyType == KeyType.cachedSharedKey ||
        keyType == KeyType.cachedPublicKey ||
        keyType == KeyType.localKey);
  }
}
