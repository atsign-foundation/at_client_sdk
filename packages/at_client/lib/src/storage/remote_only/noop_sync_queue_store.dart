import 'package:at_client/src/sync/sync_queue_store.dart';

/// A [SyncQueueStore] that persists nothing — every member is a no-op or
/// returns empty. Satisfies D-18 item 1 ("a queue which never enqueues
/// and always reports empty satisfies the contract") for
/// `RemoteOnlyAtClientStorage`: delivery happens synchronously in the
/// write-through keystore, so there is nothing left for a queue to
/// redeliver across a restart.
class NoopSyncQueueStore implements SyncQueueStore {
  const NoopSyncQueueStore();

  @override
  Iterable<String> get keys => const Iterable.empty();
  @override
  String? get(String atKey) => null;
  @override
  Future<void> put(String atKey, String record) async {}
  @override
  Future<void> delete(String atKey) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> close() async {}
}
