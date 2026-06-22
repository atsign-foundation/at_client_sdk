import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/hive.dart';

/// Creates and owns the client's local persistence: a commit-log-free Hive
/// bundle built through [HiveAtPersistenceFactory]. The keystore self-manages
/// its on-disk encryption secret from a file in the storage path (as the
/// retired `HivePersistenceManager` did), so no secret is threaded in here —
/// `AtClientPreference.keyStoreSecret` was already unused by the old
/// bootstrap.
class StorageManager {
  bool isStorageInitialized = false;

  AtClientPreference? preferences;

  final HiveAtPersistenceFactory _factory = HiveAtPersistenceFactory();
  AtPersistenceBundle? _bundle;

  StorageManager(this.preferences);

  /// The per-atSign persistence bundle. Throws [StateError] until [init].
  AtPersistenceBundle get bundle {
    final b = _bundle;
    if (b == null) {
      throw StateError('StorageManager.init() has not been called');
    }
    return b;
  }

  /// The per-atSign persistence bundle, or `null` before [init].
  AtPersistenceBundle? get bundleOrNull => _bundle;

  /// The client's commit-log-free local keystore
  /// (`bundle.keyValueStore.commitLog == null`).
  AtKeyValueStore<String, AtData, AtMetaData?> get keyValueStore =>
      bundle.keyValueStore;

  Future<void> init(String currentAtSign, List<int>? keyStoreSecret) async {
    if (!isStorageInitialized) {
      await _initStorage(currentAtSign);
    }
  }

  Future<void> _initStorage(String currentAtSign) async {
    final storagePath = preferences!.hiveStoragePath;
    if (storagePath == null) {
      throw Exception('Please set local storage path');
    }
    _bundle = await _factory.initialize(
      currentAtSign,
      HivePersistenceConfig.clientDefaults(storagePath: storagePath),
    );
    isStorageInitialized = true;
  }
}
