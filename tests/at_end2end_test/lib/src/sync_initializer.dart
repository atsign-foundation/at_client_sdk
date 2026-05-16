import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';

/// Sync helpers shared across the e2e test suite.
///
/// Two primitives, both built on the public [SyncService] API:
///
///   - [syncData] — wait until the local secondary has caught up to
///     the remote secondary as it stood at call time. Just a thin
///     wrapper around [SyncServiceWaitUntilCaughtUp.waitUntilCaughtUp]
///     in `at_client`. Replaces a fragile broadcast-listener +
///     `isSyncInProgress` flag that this class used to maintain
///     itself; the underlying primitive does the right thing now,
///     including not completing while there are still pending
///     client→server pushes in the local sync queue.
///
///   - [awaitKeyPushed] — gate on a **specific** key having been
///     pushed local→remote. Stronger guarantee than commit-id
///     equality: the listener observes the actual push event for
///     this key's wire form and completes only then. Use this when
///     a test does `put(...)` and then needs to read the value
///     from the remote side (directly or transitively) and cares
///     about correctness, not just "sync has run". Eliminates the
///     race where a listener-based completion check fires on an
///     unrelated prior sync event and the test moves on before
///     the most recent put has actually been pushed.
class E2ESyncService {
  static final _logger = AtSignLogger('E2ESyncService');

  static final E2ESyncService _singleton = E2ESyncService._internal();
  E2ESyncService._internal();
  factory E2ESyncService.getInstance() => _singleton;

  /// Returns when the local secondary has caught up to the remote
  /// secondary's commit id as observed by the first sync event after
  /// this call. Times out after [timeout].
  Future<void> syncData(
    SyncService syncSvc, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final atSign = AtClientManager.getInstance().atClient.getCurrentAtSign();
    _logger.info('syncData starting for $atSign');
    try {
      await syncSvc.waitUntilCaughtUp(timeout: timeout);
      _logger.info('syncData complete for $atSign');
    } on TimeoutException catch (e) {
      _logger.warning('syncData timed out for $atSign: ${e.message}');
      rethrow;
    }
  }

  /// Wait until a `localToRemote` push for [atKey]'s wire form has
  /// been observed in a [SyncProgress] event, then return.
  ///
  /// **Call this BEFORE the put**, not after. Pattern:
  ///
  /// ```dart
  /// final pushed = E2ESyncService.getInstance()
  ///     .awaitKeyPushed(syncSvc, atKey);
  /// final putResult = await atClient.put(atKey, value);
  /// expect(putResult, true);
  /// await pushed;
  /// ```
  ///
  /// `AtClient.put` triggers `syncService.sync()` internally after
  /// enqueueing the local commit. On a fast sync cycle the resulting
  /// push event can fire (and be missed by listeners that haven't
  /// registered yet) before any subsequent line of caller code
  /// executes. Registering the listener after the put loses that
  /// race and the gate hangs until timeout.
  ///
  /// This helper's body runs synchronously up to its first `await`
  /// — `addProgressListener` is called before the returned Future
  /// suspends — so capturing the Future before the put is enough to
  /// guarantee the listener is in place by the time the push fires.
  ///
  /// Throws [TimeoutException] when [timeout] elapses with no
  /// matching push event observed; the exception's message includes
  /// the last [recentEventCap] [SyncProgress] events the listener saw
  /// (with sync status, commit-id state, and any KeyInfo entries),
  /// to distinguish "sync never ran" from "sync ran but didn't push
  /// our key" from "sync ran on a different syncService instance".
  ///
  /// Matches by exact string equality on `atKey.toString()` — the
  /// same wire form `UpdateVerbBuilder.buildKey()` enqueues into the
  /// sync queue, so the lookup is direct.
  Future<void> awaitKeyPushed(
    SyncService syncSvc,
    AtKey atKey, {
    Duration timeout = const Duration(minutes: 2),
    int recentEventCap = 40,
  }) async {
    final target = atKey.toString();
    final completer = Completer<void>();
    final listener = _KeyPushedListener(target, completer,
        recentCap: recentEventCap, syncSvc: syncSvc);
    syncSvc.addProgressListener(listener);
    try {
      // Poke the sync service so the push runs without waiting for
      // any background timer. waitUntilCaughtUp does the same.
      syncSvc.sync();
      await completer.future.timeout(timeout, onTimeout: () {
        throw TimeoutException(
          'awaitKeyPushed: no localToRemote push observed for $target '
          'within $timeout on syncSvc#${identityHashCode(syncSvc)}. '
          'Recent SyncProgress events (newest last, ${listener.recentEvents.length} '
          'captured):\n  ${listener.recentEvents.join("\n  ")}',
          timeout,
        );
      });
      _logger.info('awaitKeyPushed: observed push for $target');
    } finally {
      syncSvc.removeProgressListener(listener);
    }
  }
}

class _KeyPushedListener extends SyncProgressListener {
  final String target;
  final Completer<void> completer;
  final int recentCap;
  final SyncService syncSvc;
  // Captures EVERY SyncProgress event with full metadata. Per-batch
  // progress events (line 721/891 in sync_service_impl.dart) have a
  // null keyInfoList and were previously invisible — those silent
  // iterations are exactly what we need to see when diagnosing a
  // timeout where the gate fires but our key isn't in any keyInfoList.
  final List<String> recentEvents = <String>[];

  _KeyPushedListener(this.target, this.completer,
      {required this.recentCap, required this.syncSvc});

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    final keys = syncProgress.keyInfoList;
    final keyDescs = (keys == null || keys.isEmpty)
        ? '-'
        : keys.map((k) => '${k.syncDirection.name}:${k.key}').join(',');
    final entry = '[svc#${identityHashCode(syncSvc)}] '
        'status=${syncProgress.syncStatus} '
        'local=${syncProgress.localCommitId} '
        'server=${syncProgress.serverCommitId} '
        'pending=${syncProgress.pendingPushCount} '
        'msg=${syncProgress.message} '
        'keys=$keyDescs';
    if (recentEvents.length >= recentCap) recentEvents.removeAt(0);
    recentEvents.add(entry);
    if (keys == null || keys.isEmpty) return;
    for (final k in keys) {
      if (k.syncDirection == SyncDirection.localToRemote && k.key == target) {
        if (!completer.isCompleted) completer.complete();
      }
    }
  }
}
