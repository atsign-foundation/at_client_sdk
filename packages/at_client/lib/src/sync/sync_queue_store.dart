/// Where an `AtSyncQueue` keeps its records: one string per atKey.
abstract class SyncQueueStore {
  Iterable<String> get keys;
  String? get(String atKey);
  Future<void> put(String atKey, String record);
  Future<void> delete(String atKey);
  Future<void> clear();
  Future<void> close();
}

/// A [SyncQueueStore] that persists nothing: a queue over it never holds an
/// entry. For a storage whose writes are delivered synchronously, so there is
/// nothing to redeliver across a restart.
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
