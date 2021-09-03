import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Manager to init local preferences
class PreferenceManager {
  AtClientPreference preferences;
  final _atSign;

  PreferenceManager(this.preferences, this._atSign);

  @deprecated
  Future<void> setPreferences() async => _persistSyncStrategy();

  @deprecated
  void _persistSyncStrategy() async {
    var syncData = AtData();
    syncData.data = preferences.syncStrategy.toString();
    var keyStoreManager = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(_atSign)!
        .getSecondaryKeyStoreManager()!;
    await keyStoreManager.getKeyStore().put('private:sync_strategy', syncData);
  }
// commented. is this required in client ?
//  void _persistCurrentAtSign() async {
//    var syncData = AtData();
//    syncData.data = currentAtSign;
//    var keyStoreManager = SecondaryKeyStoreManager.getInstance();
//    await keyStoreManager.getKeyStore().put('private:atsign', syncData);
//  }
}
