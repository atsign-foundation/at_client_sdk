import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
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

  Future<void> testInitializer(
      String atSign, String namespace, String authType) async {
    try {
      late AtChops atChops;
      AtAuthResponse? atAuthResponse;

      if (authType.toLowerCase() == 'apkam') {
        AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
        atAuthRequest.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
        atAuthRequest.atKeysFilePath =
            '${ConfigUtil.getYaml()['filePath']}/${atSign}_key.atKeys';
        atAuthResponse = await authenticate(atAuthRequest);
        atChops = createAtChopsFromAtAuthKeys(atAuthResponse.atAuthKeys!);
      } else {
        atChops = createAtChopsFromDemoKeys(atSign);
      }

      // Create the atClientManager for the atSign
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace,
              TestPreferences.getInstance().getPreference(atSign),
              atChops: atChops, enrollmentId: atAuthResponse?.enrollmentId);
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

  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    AtAuth atAuth = atAuthBase.atAuth();
    AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
    return atAuthResponse;
  }

  AtChops createAtChopsFromAtAuthKeys(AtAuthKeys atAuthKeys) {
    AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
        atAuthKeys.defaultEncryptionPublicKey!,
        atAuthKeys.defaultEncryptionPrivateKey!);
    AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
        atAuthKeys.apkamPublicKey!, atAuthKeys.apkamPrivateKey!);
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey =
        AESKey(atAuthKeys.defaultSelfEncryptionKey!);
    atChopsKeys.apkamSymmetricKey = AESKey(atAuthKeys.apkamSymmetricKey!);

    AtChops atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }

  AtChops createAtChopsFromDemoKeys(String atSign) {
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        AtCredentials
            .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY],
        AtCredentials
            .credentialsMap[atSign]![TestConstants.ENCRYPTION_PRIVATE_KEY]);
    var atPkamKeyPair = AtPkamKeyPair.create(
        AtCredentials.credentialsMap[atSign]![TestConstants.PKAM_PUBLIC_KEY],
        AtCredentials.credentialsMap[atSign]![TestConstants.PKAM_PRIVATE_KEY]);
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey = AESKey(AtCredentials
        .credentialsMap[atSign]![TestConstants.SELF_ENCRYPTION_KEY]);
    return AtChopsImpl(atChopsKeys);
  }
}
