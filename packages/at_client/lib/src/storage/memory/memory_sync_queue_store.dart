import 'package:at_client/src/sync/sync_queue_store.dart';

/// A [SyncQueueStore] whose records live in a map.
class MemorySyncQueueStore implements SyncQueueStore {
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
