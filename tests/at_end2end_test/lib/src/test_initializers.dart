import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/src/at_encryption_key_initializers.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_utils/at_logger.dart';

import 'at_credentials.dart';

class TestSuiteInitializer {
  final _logger = AtSignLogger('TestSuiteInitializer');

  static final TestSuiteInitializer _singleton =
      TestSuiteInitializer._internal();

  TestSuiteInitializer._internal();

  factory TestSuiteInitializer.getInstance() {
    return _singleton;
  }

  Future<void> testInitializer(String atSign, String namespace) async {
    try {
      // Create the atClientManager for the atSign
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace,
              TestPreferences.getInstance().getPreference(atSign));
      // Set Encryption Keys for currentAtSign
      await AtEncryptionKeysLoader.getInstance()
          .setEncryptionKeys(atClientManager.atClient, atSign);
      await E2ESyncService.getInstance()
          .syncData(atClientManager.atClient.syncService);

      // verify if the local key is set to local secondary
      var result = await atClientManager.atClient
          .getLocalSecondary()!
          .getEncryptionPublicKey(atSign);
      _logger.finer('encryption public key set to local key-store: $result');
      assert(result ==
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY]);
      _logger.info('Initial setup the $atSign is complete');
    } on Exception catch (e) {
      print('Exception in setting the encryption: $e');
    }
  }
}
