import 'package:hive/hive.dart';

/// Where an `AtSyncQueue` keeps its records: one string per atKey.
abstract class SyncQueueStore {
  Iterable<String> get keys;
  String? get(String atKey);
  Future<void> put(String atKey, String record);
  Future<void> delete(String atKey);
  Future<void> clear();
  Future<void> close();
}

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

/// A [SyncQueueStore] on a Hive box.
class HiveBoxSyncQueueStore implements SyncQueueStore {
  HiveBoxSyncQueueStore(this._box);
  final Box<String> _box;

  @override
  Iterable<String> get keys => _box.keys.cast<String>();
  @override
  String? get(String atKey) => _box.get(atKey);
  @override
  Future<void> put(String atKey, String record) => _box.put(atKey, record);
  @override
  Future<void> delete(String atKey) => _box.delete(atKey);
  @override
  Future<void> clear() => _box.clear();
  @override
  Future<void> close() => _box.close();
}
