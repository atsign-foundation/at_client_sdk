import 'dart:async';

import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/sync/sync_queue_store.dart';

/// An open sync queue for [atSign] whose records live in a map, for a
/// `LocalSecondary` a test builds by hand.
AtSyncQueue memorySyncQueue([String atSign = '@test']) {
  final queue = AtSyncQueue(atSign: atSign);
  unawaited(queue.open(store: _MapSyncQueueStore()));
  // NOTE: over a map store open() completes before it returns, which is
  // what lets this hand back a queue without awaiting.
  if (!queue.isOpen) {
    throw StateError('the sync queue for $atSign did not open synchronously');
  }
  return queue;
}

class _MapSyncQueueStore implements SyncQueueStore {
  final Map<String, String> _records = {};

  @override
  Iterable<String> get keys => _records.keys.toList();

  @override
  String? get(String atKey) => _records[atKey];

  @override
  Future<void> put(String atKey, String record) async =>
      _records[atKey] = record;

  @override
  Future<void> delete(String atKey) async => _records.remove(atKey);

  @override
  Future<void> clear() async => _records.clear();

  @override
  Future<void> close() async {}
}
