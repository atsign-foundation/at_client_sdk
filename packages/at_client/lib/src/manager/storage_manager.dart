import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Manager to create local storage. Wraps a [HiveAtPersistenceFactory]
/// so each AtClient owns one factory + one per-atSign bundle, replacing
/// the historical pattern of reaching into shared singletons via
/// `*Manager*.getInstance()`.
class StorageManager {
  bool isStorageInitialized = false;

  AtClientPreference? preferences;

  /// Factory that owns the per-atSign persistence lifecycle. New
  /// instance per StorageManager → independent lifecycle per AtClient.
  final HiveAtPersistenceFactory persistenceFactory =
      HiveAtPersistenceFactory();

  /// The per-atSign persistence bundle produced by [persistenceFactory]
  /// during [init]. Null until [init] has run successfully. Holds the
  /// keystore, commit log, access log and notification keystore that
  /// the rest of at_client reads.
  AtPersistenceBundle? bundle;

  StorageManager(this.preferences);

  Future<void> init(String currentAtSign, List<int>? keyStoreSecret) async {
    if (!isStorageInitialized) {
      await _initStorage(currentAtSign, keyStoreSecret);
    }
  }

  Future<void> _initStorage(
      String currentAtSign, List<int>? keyStoreSecret) async {
    var storagePath = preferences!.hiveStoragePath;
    var commitLogPath = preferences!.commitLogPath;

    if (storagePath == null || commitLogPath == null) {
      throw Exception('Please set local storage paths');
    }

    bundle = await persistenceFactory.initialize(
      currentAtSign,
      HivePersistenceConfig(
        storagePath: storagePath,
        commitLogPath: commitLogPath,
        accessLogPath: commitLogPath,
        notificationStoragePath: storagePath,
        enableCommitId: false,
      ),
    );
    bundle!.scheduleKeyExpireTask(
        preferences?.expiryCheckTimeInterval.inMinutes);
    isStorageInitialized = true;
  }
}
