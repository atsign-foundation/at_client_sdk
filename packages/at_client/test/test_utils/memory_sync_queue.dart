import 'dart:async';

import 'package:at_client/src/storage/memory/memory_sync_queue_store.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';

/// An open sync queue for [atSign] whose records live in a map, for a
/// `LocalSecondary` a test builds by hand.
AtSyncQueue memorySyncQueue([String atSign = '@test']) {
  final queue = AtSyncQueue(atSign: atSign);
  unawaited(queue.open(store: MemorySyncQueueStore()));
  // NOTE: over a map store open() completes before it returns, which is
  // what lets this hand back a queue without awaiting.
  if (!queue.isOpen) {
    throw StateError('the sync queue for $atSign did not open synchronously');
  }
  return queue;
}
