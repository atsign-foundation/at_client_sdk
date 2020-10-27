import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';

/// Manager to create local storage
class StorageManager {
  static final StorageManager _singleton = StorageManager._internal();

  StorageManager._internal();

  factory StorageManager.getInstance() {
    return _singleton;
  }

  bool isStorageInitialized = false;

  AtClientPreference preferences;

  StorageManager(this.preferences);

  void init(String currentAtSign, List<int> keyStoreSecret) async {
    if (!isStorageInitialized) {
      await _initStorage(currentAtSign, keyStoreSecret);
    }
  }

  void _initStorage(String currentAtSign, List<int> keyStoreSecret) async {
    print('initializing storage');
    var storagePath = preferences.hiveStoragePath;
    var commitLogPath = preferences.commitLogPath;

    if (storagePath == null || commitLogPath == null) {
      throw Exception('Please set local storage paths');
    }
    var commitLogKeyStore = CommitLogKeyStore.getInstance();
    commitLogKeyStore.enableCommitId = false;
    await commitLogKeyStore.init(
        'commit_log_' + AtUtils.getShaForAtSign(currentAtSign), commitLogPath);
    // Initialize Persistence
    // var manager = client_storage.HivePersistenceManager.getInstance();
    var manager = HivePersistenceManager.getInstance();

    await manager.init(currentAtSign, storagePath);
    await manager.openVault(currentAtSign, hiveSecret: keyStoreSecret);
    var keyStoreManager = SecondaryKeyStoreManager.getInstance();
    keyStoreManager.init();
    isStorageInitialized = true;
  }
}
