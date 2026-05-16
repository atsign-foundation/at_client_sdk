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
  /// The listener is registered **before** anything that could
  /// trigger the push (the caller's `put` typically happens right
  /// after this helper is set up — or, more often, the caller does
  /// `put` first and immediately calls this; the broadcast stream
  /// will surface the push event whether registration happens just
  /// before or just after the `put`, since the push doesn't complete
  /// until later in the sync cycle).
  ///
  /// Throws [TimeoutException] when [timeout] elapses with no
  /// matching push event observed; the exception's message includes
  /// the last [recentEventCap] KeyInfo entries the listener saw, to
  /// distinguish "sync never ran" from "sync ran but didn't include
  /// our key" from "sync ran on a different direction".
  ///
  /// Matches by exact string equality on `atKey.toString()` — the
  /// same wire form `UpdateVerbBuilder.buildKey()` enqueues into the
  /// sync queue, so the lookup is direct.
  Future<void> awaitKeyPushed(
    SyncService syncSvc,
    AtKey atKey, {
    Duration timeout = const Duration(minutes: 2),
    int recentEventCap = 20,
  }) async {
    final target = atKey.toString();
    final completer = Completer<void>();
    final listener =
        _KeyPushedListener(target, completer, recentCap: recentEventCap);
    syncSvc.addProgressListener(listener);
    try {
      // Poke the sync service so the push runs without waiting for
      // any background timer. waitUntilCaughtUp does the same.
      syncSvc.sync();
      await completer.future.timeout(timeout, onTimeout: () {
        throw TimeoutException(
          'awaitKeyPushed: no localToRemote push observed for $target '
          'within $timeout. Recent KeyInfo entries (newest last): '
          '${listener.recentKeyInfos}',
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
  final List<String> recentKeyInfos = <String>[];

  _KeyPushedListener(this.target, this.completer, {required this.recentCap});

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    final keys = syncProgress.keyInfoList;
    if (keys == null || keys.isEmpty) return;
    for (final k in keys) {
      if (recentKeyInfos.length >= recentCap) {
        recentKeyInfos.removeAt(0);
      }
      recentKeyInfos.add('${k.syncDirection.name}:${k.key}');
      if (k.syncDirection == SyncDirection.localToRemote && k.key == target) {
        if (!completer.isCompleted) completer.complete();
      }
    }
  }
}
