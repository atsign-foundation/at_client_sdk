import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Manager to create local storage
class StorageManager {
  bool isStorageInitialized = false;

  AtClientPreference? preferences;

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
    var atCommitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(
        currentAtSign,
        commitLogPath: commitLogPath,
        enableCommitId: false);
    // Initialize Persistence
    var hivePersistenceManager = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(currentAtSign)!
        .getHivePersistenceManager()!;
    await hivePersistenceManager.init(storagePath);
    var hiveKeyStore = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(currentAtSign)!
        .getSecondaryKeyStore()!;
    hiveKeyStore.commitLog = atCommitLog;
    var keyStoreManager = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(currentAtSign)!
        .getSecondaryKeyStoreManager()!;
    await hiveKeyStore.initialize();
    keyStoreManager.keyStore = hiveKeyStore;
    // The persistence-layer cron sweep is intentionally not scheduled
    // here. AtClientImpl owns an event-driven expiry timer that re-arms
    // off LocalSecondary's data-event stream and drives sweeps via
    // LocalSecondary.deleteExpiredKeys() — whose deletes go through
    // _delete and are visible to subscribers, unlike the cron path
    // which would call keyStore.remove directly and bypass the event
    // bus.
    isStorageInitialized = true;
  }
}
