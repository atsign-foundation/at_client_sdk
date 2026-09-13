import 'package:at_client/at_client.dart';

class TestUtil {
  static AtClientPreference getPreferenceLocal() {
    var preference = AtClientPreference();
    preference.cramSecret = '<cram_secret>';
    preference.rootDomain = 'vip.ve.atsign.zone';
    return preference;
  }

  /// The Hive store a test client for [atSign] opens, closed with it.
  static AtClientStorage getStorageLocal(String atSign) => HiveAtClientStorage(
      atSign: atSign, storagePath: 'hive/client', closedByClient: true);

  /// Opens [atSign]'s client from its keyfile in the default keys
  /// directory and makes it the manager's current client.
  static Future<AtClientManager> openAsCurrent(String atSign) async {
    final client = await Atsign(atSign).open(
        keys: FileAtKeysIo(),
        preference: getPreferenceLocal(),
        namespace: 'me',
        storage: getStorageLocal(atSign));
    return AtClientManager.getInstance()..use(client);
  }
}
