import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// The default storage: a Hive keystore and sync queue under [storagePath].
class HiveAtClientStorage extends AtClientStorageBase {
  HiveAtClientStorage({required this.atSign, required this.storagePath});

  final String atSign;
  final String storagePath;

  StorageManager? _manager;
  AtSyncQueue? _queue;
  bool _closed = false;

  // NOTE: the persistence layer opens every box on the global Hive instance,
  // named by atSign, so two of these for one atSign would share boxes whatever
  // their paths. One open per atSign per isolate.
  static final Map<String, HiveAtClientStorage> _openByAtSign = {};

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
    if (_closed) throw StateError('storage for $atSign has been closed');
    if (_manager != null) return;
    final other = _openByAtSign[atSign];
    if (other != null && !identical(other, this)) {
      throw StateError('another HiveAtClientStorage already holds $atSign\'s '
          'boxes in this isolate (at ${other.storagePath}); stop the client '
          'holding it before opening one at $storagePath');
    }
    final manager =
        StorageManager(AtClientPreference()..hiveStoragePath = storagePath);
    await manager.init(atSign, null);
    final queue = AtSyncQueue(atSign: atSign);
    await queue.open();
    _manager = manager;
    _queue = queue;
    _openByAtSign[atSign] = this;
  }

  @override
  Future<void> clearData() async {
    await _openManager.bundle.clear();
    await syncQueue.clear();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    dropClaim();
    await _queue?.close();
    await _manager?.bundleOrNull?.close();
    if (identical(_openByAtSign[atSign], this)) _openByAtSign.remove(atSign);
  }
}
