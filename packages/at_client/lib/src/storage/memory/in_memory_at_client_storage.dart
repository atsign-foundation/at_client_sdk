import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/memory/memory_at_key_value_store.dart';
import 'package:at_client/src/storage/memory/memory_sync_queue_store.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Keystore and sync queue held in memory, in pure Dart: nothing reaches
/// disk, nothing outlives [close], and each instance is a store of its own.
class InMemoryAtClientStorage extends AtClientStorageBase {
  InMemoryAtClientStorage({required this.atSign, super.closedByClient});

  final String atSign;

  static int _created = 0;

  /// Unique to this instance in this process, so two in-memory stores are
  /// never refused as one.
  final int _id = _created++;

  MemoryAtKeyValueStore? _keyStore;
  AtSyncQueue? _queue;

  @override
  String get location => 'memory#$_id';

  @override
  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore =>
      _keyStore ?? (throw StateError('storage for $atSign is not open'));

  @override
  AtSyncQueue get syncQueue =>
      _queue ?? (throw StateError('storage for $atSign is not open'));

  @override
  Future<void> openBackend() async {
    if (_keyStore != null) return;
    final queue = AtSyncQueue(atSign: atSign);
    await queue.open(store: MemorySyncQueueStore());
    _keyStore = MemoryAtKeyValueStore(atSign);
    _queue = queue;
  }

  @override
  Future<void> clearData() async {
    await (_keyStore ?? (throw StateError('storage for $atSign is not open')))
        .clear();
    await syncQueue.clear();
  }

  @override
  Future<void> closeBackend() async {
    await _queue?.close();
    await _keyStore?.close();
  }
}
