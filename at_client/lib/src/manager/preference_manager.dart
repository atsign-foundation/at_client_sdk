import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Manager to init local preferences
class PreferenceManager {
  AtClientPreference preferences;

  PreferenceManager(this.preferences);

  void setPreferences() async {
    _persistSyncStrategy();
  }

  void _persistSyncStrategy() async {
    var syncData = AtData();
    syncData.data = preferences.syncStrategy.toString();
    var keyStoreManager = SecondaryKeyStoreManager.getInstance();
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
