import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/src/at_encryption_key_initializers.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';

import 'at_credentials.dart';

class TestSuiteInitializer {
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
              TestPreferences.getInstance().getPreference(atSign),
              atChops: AtEncryptionKeysLoader.getInstance()
                  .createAtChopsFromDemoKeys(atSign));
      // Set Encryption Keys for currentAtSign
      await AtEncryptionKeysLoader.getInstance()
          .setEncryptionKeys(atClientManager.atClient, atSign);
      await E2ESyncService.getInstance().syncData(
          atClientManager.atClient.syncService,
          syncOptions: SyncOptions()..waitForFullSyncToComplete = true);

      // verify if the public key is in the local secondary
      var result = await atClientManager.atClient
          .getLocalSecondary()!
          .getEncryptionPublicKey(atSign);
      assert(result ==
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY]);

      // verify if the private key is in the local secondary
      result = await atClientManager.atClient
          .getLocalSecondary()!
          .getEncryptionPrivateKey();
      assert(result ==
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PRIVATE_KEY]);
    } on Exception catch (e) {
      print('Exception in setting the encryption: $e');
    }
  }
}
