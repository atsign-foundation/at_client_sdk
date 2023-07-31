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
    var manager = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(currentAtSign)!
        .getHivePersistenceManager()!;
    await manager.init(storagePath);
    var hiveKeyStore = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(currentAtSign)!
        .getSecondaryKeyStore()!;
    hiveKeyStore.commitLog = atCommitLog;
    var keyStoreManager = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(currentAtSign)!
        .getSecondaryKeyStoreManager()!;
    await hiveKeyStore.initialize();
    keyStoreManager.keyStore = hiveKeyStore;
    isStorageInitialized = true;
  }

  Future<void> stopInstances(String currentAtSign) async {
    AtCommitLog? atCommitLog = await AtCommitLogManagerImpl.getInstance()
        .getCommitLog(currentAtSign,
            commitLogPath: preferences?.commitLogPath, enableCommitId: false);

    HivePersistenceManager hiveManager =
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(currentAtSign)!
            .getHivePersistenceManager()!;

    SecondaryKeyStore hiveKeyStore =
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(currentAtSign)!
            .getSecondaryKeyStore()!;

    await (hiveKeyStore.commitLog as AtCommitLog).close();
    await hiveManager.close();
    await atCommitLog?.close();
  }
}
