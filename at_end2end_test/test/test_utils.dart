import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/test_constants.dart';
import 'package:at_utils/at_logger.dart';

import 'at_credentials.dart';

class TestUtils {
  static final atClientPreferences = <String, AtClientPreference>{};
  static final _logger = AtSignLogger('TestUtils');

  static AtClientPreference getPreference(String atSign) {
    // If atClientPreferences does not contain the preference of an atSign
    // create new preference and add to map.
    if (atClientPreferences.containsKey(atSign)) {
      return atClientPreferences[atSign]!;
    }
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'test/hive/client';
    preference.commitLogPath = 'test/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.privateKey =
        AtCredentials.credentialsMap[atSign]![TestConstants.PKAM_PRIVATE_KEY];
    preference.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
    atClientPreferences.putIfAbsent(atSign, () => preference);
    return preference;
  }

  static Future<void> setEncryptionKeys(String atSign) async {
    try {
      final atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, 'me', getPreference(atSign));
      var atClient = atClientManager.atClient;
      var metadata = Metadata();
      metadata.namespaceAware = false;
      bool result;

      //Set encryption private key
      result = await atClient.getLocalSecondary()!.putValue(
          AT_ENCRYPTION_PRIVATE_KEY,
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PRIVATE_KEY]);
      _logger.info('Encryption private key is set successfully $result');

      // set encryption public key. should be synced
      metadata.isPublic = true;
      var atKey = AtKey()
        ..key = 'publickey'
        ..metadata = metadata;
      result = await atClient.put(
          atKey,
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY]);
      _logger.info('Encryption public key is set successfully $result');

      // set self encryption key
      result = await atClient.getLocalSecondary()!.putValue(
          AT_ENCRYPTION_SELF_KEY,
          AtCredentials
              .credentialsMap[atSign]![TestConstants.SELF_ENCRYPTION_KEY]);
      _logger.info('Self encryption key is set successfully $result');
    } on Exception catch (e) {
      _logger.severe(e.toString());
    }
  }
}
