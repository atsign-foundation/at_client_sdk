import 'package:at_client/at_client_io.dart';
import 'package:at_client/hive.dart';

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
    final preference = getPreferenceLocal();
    final client = await Atsign(atSign).open(
        keys: FileAtKeysIo(),
        preference: preference,
        namespace: 'me',
        storage: getStorageLocal(atSign),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: CacheableSecondaryAddressFinder(
            preference.rootDomain, preference.rootPort));
    return AtClientManager.getInstance()..use(client);
  }
}
