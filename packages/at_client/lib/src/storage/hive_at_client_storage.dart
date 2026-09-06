import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/hive.dart';

/// The default storage: a Hive keystore and sync queue under [storagePath].
class HiveAtClientStorage extends AtClientStorageBase {
  HiveAtClientStorage({required this.atSign, required this.storagePath});

  final String atSign;
  final String storagePath;

  StorageManager? _manager;
  AtSyncQueue? _queue;

  /// The store this points at: the canonical directory `HiveInstances.forPath`
  /// resolves the instance by, plus the atSign the box is named from. Both
  /// halves are needed — two atSigns under one directory are two boxes and
  /// share nothing, while one atSign under one directory is a single box
  /// however many of these point at it.
  @override
  String get location =>
      '${HiveInstances.canonicalPathFor(storagePath)}::$atSign';

  /// The persistence bundle, or `null` before the first [attach].
  AtPersistenceBundle? get bundle => _manager?.bundleOrNull;

  @override
  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore =>
      _openManager.keyValueStore;

  @override
  AtSyncQueue get syncQueue {
    final q = _queue;
    if (q == null) throw StateError('storage for $atSign is not open');
    return q;
  }

  StorageManager get _openManager {
    final m = _manager;
    if (m == null) throw StateError('storage for $atSign is not open');
    return m;
  }

  @override
  Future<void> openBackend() async {
    if (_manager != null) return;
    final manager =
        StorageManager(AtClientPreference()..hiveStoragePath = storagePath);
    await manager.init(atSign, null);
    final queue = AtSyncQueue(atSign: atSign, storagePath: storagePath);
    await queue.open();
    _manager = manager;
    _queue = queue;
  }

  @override
  Future<void> clearData() async {
    await _openManager.bundle.clear();
    await syncQueue.clear();
  }

  @override
  Future<void> closeBackend() async {
    await _queue?.close();
    await _manager?.bundleOrNull?.close();
  }
}
