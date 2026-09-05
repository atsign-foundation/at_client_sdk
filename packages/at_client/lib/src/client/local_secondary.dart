import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/data_event.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/collections/collections.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

/// Contains methods to execute verb on local secondary storage using [executeVerb]
/// Set [AtClientPreference.isLocalStoreRequired] to true and other preferences that your app needs.
/// Delete and Update commands will be synced to the server
class LocalSecondary implements Secondary {
  final AtClient _atClient;

  late final AtSignLogger _logger;

  /// Local keystore used to store data for the current atSign.
  /// Commit-log-free (`keyStore.commitLog == null`): client bundles
  /// track sync via [AtSyncQueue] + the synced-commit-id watermark,
  /// not the commit log.
  AtKeyValueStore<String, AtData, AtMetaData?>? keyStore;

  /// Sink for keystore-mutation events. Wired by `AtClientImpl` at
  /// construction to its `emitDataEvent`; left null by
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
  ///
  /// **Why a per-key fired map rather than a single `(since, asOf]`
  /// watermark** (the alternative the keystore's
  /// [AtKeyValueStore.peekNewlyAvailable] is built around): the two
  /// agree for forward-moving `availableAt`, but differ when a record's
  /// TTB is re-written to an instant at-or-before the current
  /// watermark — the fired map re-fires it on the next sweep (the value
  /// changed), a watermark window never would. at_client keeps the map
  /// to preserve that re-write semantic; [keysWithAvailableAtAtOrBefore]
  /// applies it as a filter on top of `peekNewlyAvailable`.
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

  /// Immutable snapshot of the in-progress writes set. Test-only
  /// seam — production code consults [isWriteInProgress] per key.
  @visibleForTesting
  Set<String> get writesInProgressForTest =>
      Set<String>.unmodifiable(_writesInProgress);

  LocalSecondary(
    this._atClient, {
    this.keyStore,
    AtSyncQueue? syncQueue,
    void Function(DataEvent)? onEvent,
  })  : _syncQueue = syncQueue,
        _onEvent = onEvent {
    _logger = AtSignLogger('LocalSecondary (${_atClient.getCurrentAtSign()})');
    keyStore ??= _atClient.persistenceBundle?.keyValueStore;
  }

  /// Idempotent lazy-open of the sync queue. The first caller wins
  /// the open; concurrent callers await the same in-flight future so
  /// we never call `Hive.openBox` twice for the same atSign.
  ///
  /// Must run AFTER the at_persistence_secondary_server's
  /// `HiveAtPersistenceFactory.initialize(...)` has called
  /// `Hive.init(...)`, which is guaranteed by the
  /// [StorageManager] init ordering during AtClient init. We
  /// intentionally do not call `Hive.init` here — rerunning it with a
  /// different path would silently misroute the box.
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
      // Null is a legal answer, not a failure: a LocalSecondary built around
      // an injected keystore has no hiveStoragePath and never needed one.
      // AtSyncQueue then uses the global instance, exactly as it always did.
      final q = AtSyncQueue(
          atSign: atSign,
          storagePath: _atClient.getPreferences()?.hiveStoragePath);
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
  /// Removes [atKey]'s queue entry only while it is still the version
  /// stamped [seq]; returns whether it removed. The drain's success-path
  /// removal — see [AtSyncQueue.removeIfUnchanged] for why unconditional
  /// removal there loses whichever write replaced the entry mid-flight.
  Future<bool> removeFromSyncQueueIfUnchanged(String atKey, int seq) async {
    final q = await _ensureSyncQueueOpen();
    return q.removeIfUnchanged(atKey, seq);
  }

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
  /// Per-key dedup is by construction: a second [AtSyncQueue.enqueue]
  /// for the same [atKey] overwrites the first (UPDATE→DELETE
  /// collapses to DELETE). The commit-log-free keystore produces no
  /// sequence numbers, so there is nothing to reconcile between the
  /// superseded and current op.
  Future<void> _enqueueForSync(
    String atKey,
    SyncQueueOp op, {
    required bool cameFromServer,
  }) async {
    if (cameFromServer) return;
    if (!shouldEnqueueForSync(atKey, op)) return;
    try {
      final q = await _ensureSyncQueueOpen();
      await q.enqueue(atKey, op);
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
  /// server-originated change into local storage, or filing a value
  /// it has just fetched from the atServer. The flag tells
  /// `_update` / `_delete` to skip the sync-queue enqueue — the
  /// server already has the entry; bouncing it back would be a loop,
  /// and a queued entry carries only the key's name, so a later drain
  /// would send whatever local storage held by then.
  ///
  /// Grep for the flag rather than trusting a list here: this said
  /// "today only `SyncServiceImpl._pullToLocal` does this" while
  /// `legacy_encryption.dart` had long been caching a fetched public
  /// key the same way.
  @override
  Future<String?> executeVerb(VerbBuilder builder,
      {@Deprecated('Inert: nothing reads it, so passing it suppresses '
          'nothing. Whether a local write is enqueued for '
          'client→server sync is decided by cameFromServer. '
          'Removed in 4.0.')
      bool? sync,
      bool cameFromServer = false}) async {
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
            final AtData? fetchedBack = await keyStore!.get(updateKey);
            _logger.finest('After keyStore.get fetched back'
                ' $updateKey'
                ' cameFromServer: $cameFromServer'
                ' ttl ${fetchedBack?.metaData?.ttl}'
                ' expiresAt ${fetchedBack?.metaData?.expiresAt}'
                ' ttb ${fetchedBack?.metaData?.ttb}'
                ' availableAt ${fetchedBack?.metaData?.availableAt}'
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
      await _enqueueForSync(
        updateKey,
        syncQueueOp,
        cameFromServer: cameFromServer,
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

  /// [isExpiry] marks a deletion the TTL sweep is performing rather than one
  /// an enrollment asked for, and skips the enrollment authorization check.
  ///
  /// Reclaiming an expired record is storage internals, not an operation on
  /// anyone's data: the record has already ceased to exist as far as every
  /// reader is concerned, and the sweep is driven by a timer rather than by
  /// the enrollment whose scope the check tests. Refusing it leaves bytes
  /// nothing can read and — before the expiry timer learned to back off — a
  /// record the sweep retried forever. The scoping the check exists to
  /// enforce is unaffected: an expiry deletion is `localOnly`, so it is never
  /// enqueued for sync and cannot reach anyone else's copy.
  Future<String> _delete(DeleteVerbBuilder builder,
      {bool cameFromServer = false,
      bool localOnly = false,
      bool isExpiry = false}) async {
    var deleteKey = builder.buildKey();
    if (!isExpiry &&
        !await isEnrollmentAuthorizedForOperation(deleteKey, builder)) {
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
      // case) we DO enqueue, even if the key never existed locally —
      // the user's intent is "make sure it's gone everywhere", and a
      // delete for a never-synced record costs only a commitId++
      // server-side.
      if (!localOnly) {
        await _enqueueForSync(
          deleteKey,
          SyncQueueOp.delete,
          cameFromServer: cameFromServer,
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
  /// keystore's TTL bookkeeping. Each deletion goes through
  /// [_delete], which fires a [DataDeleted] on [AtClient.dataEvents]
  /// — so subscribers see expirations the same way they see any other
  /// delete. Returns the number of keys removed.
  ///
  /// Callers arming a timer via [AtClient.dataEvents] should suppress
  /// re-arms while a sweep is in flight (the events fired during this
  /// method would otherwise cause N redundant re-arms).
  /// `AtClientImpl._onExpiryFire` does this via a `_sweepInFlight`
  /// flag.
  ///
  /// Returns 0 (no-op) when there is no local keystore.
  Future<int> deleteExpiredKeys() async {
    final ks = keyStore;
    if (ks == null) {
      _logger.shout('deleteExpiredKeys called with no local keyStore');
      return 0;
    }
    final expired = await (await ks.getExpiredKeys()).toList();
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
        // isExpiry: true — reclaiming an expired record is storage internals,
        // not an operation an enrollment is performing, so it is not subject
        // to that enrollment's namespace scope. Without it a client whose
        // enrollment does not cover a record's namespace can never reclaim it:
        // the record is pulled into local storage by sync, expires, and then
        // fails this delete forever. `_nskeylock` records reach exactly that
        // state — created remote-only by MintLock, synced down like any other
        // key, and released by ttl alone.
        await _delete(builder, localOnly: true, isExpiry: true);
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
        return await _atClient
            .getRemoteSecondary()!
            .executeCommand(command, auth: true);
      }
      List<String?> keys =
          await (await keyStore!.getKeys(regex: builder.regex)).toList();
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

  /// The epoch-zero (UTC) watermark — the "look at the whole history"
  /// lower bound for [AtKeyValueStore.peekNewlyAvailable]'s exclusive
  /// `since`. Every real `availableAt` is strictly after it.
  static final DateTime _epoch =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Earliest pending `expiresAt` across keys with TTL, or `null` if
  /// none. Delegates to [KeyValueStore.nextExpiresAt], answered from
  /// the backend's expiry index (not a full-store scan).
  ///
  /// Returns `null` when there is no local keystore.
  Future<DateTime?> nextExpiryAt() async => await keyStore?.nextExpiresAt();

  /// Earliest pending future `availableAt` across keys with TTB, or
  /// `null` if none. Delegates to [AtKeyValueStore.nextAvailableAt],
  /// which only considers not-yet-born keys (`availableAt > now`) — so
  /// already-fired past crossings are excluded by construction, with
  /// no need to consult [_firedAvailableAt].
  Future<DateTime?> nextAvailableAt() async =>
      await keyStore?.nextAvailableAt();

  /// Keys whose `availableAt` is at-or-before [cutoff] and that
  /// haven't already been fired for the same crossing
  /// ([_firedAvailableAt]). Drives `AtClientImpl._onAvailableFire`'s
  /// visibility-onset sweep.
  ///
  /// Sources the born-key set from [AtKeyValueStore.peekNewlyAvailable]
  /// over the whole-history window `(epoch, cutoff]`, then applies the
  /// fired-map suppression on top (see the class-level note on why the
  /// per-key fired map is kept rather than a single watermark).
  Future<List<String>> keysWithAvailableAtAtOrBefore(DateTime cutoff) async {
    final ks = keyStore;
    if (ks == null) return const [];
    final born =
        await (await ks.peekNewlyAvailable(since: _epoch, asOf: cutoff))
            .toList();
    final result = <String>[];
    for (final key in born) {
      final avail = (await ks.getMeta(key))?.availableAt;
      if (avail == null) continue;
      final fired = _firedAvailableAt[key];
      if (fired != null && fired.isAtSameMomentAs(avail)) continue;
      result.add(key);
    }
    return result;
  }

  /// Records that the available-timer sweep just emitted
  /// `DataUpdated` for [key], so subsequent sweeps don't re-fire
  /// for the same `availableAt` crossing. A subsequent `_update`
  /// that rewrites the record with a new future `availableAt`
  /// (different from the recorded one) re-enables firing.
  Future<void> dropAvailabilityCacheEntry(String key) async {
    final avail = (await keyStore?.getMeta(key))?.availableAt;
    if (avail != null) {
      _firedAvailableAt[key] = avail;
    }
  }

  /// Pre-marks every key whose `availableAt` is at or before [now] as
  /// "already fired" in the in-memory [_firedAvailableAt] map. The
  /// availability sweep (`AtClientImpl._onAvailableFire`) checks this
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
  Future<void> seedAvailabilityFiredAsOf(DateTime now) async {
    final ks = keyStore;
    if (ks == null) return;
    final born =
        await (await ks.peekNewlyAvailable(since: _epoch, asOf: now)).toList();
    for (final key in born) {
      final avail = (await ks.getMeta(key))?.availableAt;
      if (avail != null) _firedAvailableAt[key] = avail;
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
    // Commit-log-free: `put` returns `null` (no sequence number) on
    // success and throws on failure. Reaching the return means the
    // write landed.
    var atData = AtData()..data = value;
    await keyStore!.put(key, atData);
    return true;
  }

  Future<bool> isEnrollmentAuthorizedForOperation(
      String key, VerbBuilder verbBuilder) async {
    // Do whatever you want with "local" keys
    if (key.startsWith('local:')) {
      return true;
    }
    // if there is no enrollment, return true
    await getEnrollmentDetails();
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

  /// The enrollment record for the enrollment this client authenticates as,
  /// memoised for the life of this object. Null when the client holds no
  /// enrollment id — it is authenticating with the atSign's own keys and has
  /// no id to fetch a record by.
  ///
  /// Public because the PQ startup reconciles the keyfile's own snapshot of
  /// `namespaces`/`appName`/`deviceName` against this record. Two readers of
  /// one record are two chances to describe it differently, so the second
  /// caller shares this one rather than issuing its own `enroll:fetch`.
  Future<Enrollment?> getEnrollmentDetails() async =>
      enrollment ??= await _getEnrollmentDetails();

  /// Always goes to the atServer. There is deliberately no durable cache: the
  /// only reuse is the in-memory memo in [getEnrollmentDetails], which makes
  /// this one fetch per client rather than per call.
  ///
  /// There used to be a local-keystore cache here and **it could never hit** —
  /// the read looked for `local:<enrollmentId><atSign>` while the write went to
  /// `<enrollmentId>.new.enrollments.__manage<atSign>`, which is the atServer's
  /// own naming for an enrollment record rather than a private cache key.
  /// Nothing in the workspace read what it wrote; the chain sweep gets its
  /// records from a remote `enroll:list`, where that string is only a key in
  /// the response map.
  ///
  /// Making the cache hit would have been the wrong repair. A client re-reads
  /// this record on every start precisely so that a grant changed since last
  /// time is noticed, and a cache that worked would hide exactly that.
  Future<Enrollment?> _getEnrollmentDetails() async {
    if (_atClient.enrollmentId == null) {
      return null;
    }

    String? enrollmentInfoFromServer;
    Object? fetchFailure;
    try {
      enrollmentInfoFromServer = await _atClient
          .getRemoteSecondary()
          ?.executeCommand(
              'enroll:fetch:{"enrollmentId":"${_atClient.enrollmentId}"}\n',
              auth: true);
    } on AtException catch (e) {
      fetchFailure = e;
    } on AtLookUpException catch (e) {
      fetchFailure = e;
    }

    // Both catches above used to log at `finer` and fall through to a `!` on
    // this value, so an unreachable atServer surfaced as "Null check operator
    // used on a null value" from a line that mentions neither the enrollment
    // nor the fetch — with the exception that explains it discarded at a level
    // nobody runs at.
    if (enrollmentInfoFromServer == null) {
      throw AtKeyNotFoundException('Failed to fetch the enrollment record for '
          '${_atClient.enrollmentId} from the atServer'
          '${fetchFailure == null ? '' : ': $fetchFailure'}');
    }

    enrollmentInfoFromServer =
        enrollmentInfoFromServer.replaceFirst(RegExp('^data:'), '');
    Map enrollmentDetailsMap = jsonDecode(enrollmentInfoFromServer);
    _logger.info('Enrollment Details Map : $enrollmentDetailsMap');
    enrollment = Enrollment()
      ..appName = enrollmentDetailsMap['appName']
      ..deviceName = enrollmentDetailsMap['deviceName']
      ..namespace = enrollmentDetailsMap['namespace']
      ..encryptedAPKAMSymmetricKey =
          enrollmentDetailsMap['encryptedAPKAMSymmetricKey'];

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
