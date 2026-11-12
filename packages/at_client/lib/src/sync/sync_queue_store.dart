/// Where an `AtSyncQueue` keeps its records: one string per atKey.
abstract class SyncQueueStore {
  Iterable<String> get keys;
  String? get(String atKey);
  Future<void> put(String atKey, String record);
  Future<void> delete(String atKey);
  Future<void> clear();
  Future<void> close();
}
