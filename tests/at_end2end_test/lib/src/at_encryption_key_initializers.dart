import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import '../utils/test_constants.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demo_data;
import 'package:at_chops/at_chops.dart';

/// The class is responsible for loading all the encryption of the atSign to the
/// local secondary keystore.
///
/// Setting the class as a singleton class because of multiple instances of the class
/// might cause the inconsistency on setting the encryption keys.
class AtEncryptionKeysLoader {
  static final _logger = AtSignLogger('AtEncryptionKeysLoader');

  static final AtEncryptionKeysLoader _singleton =
      AtEncryptionKeysLoader._internal();

  AtEncryptionKeysLoader._internal();

  factory AtEncryptionKeysLoader.getInstance() {
    return _singleton;
  }

  /// Stores the encryption keys to the local secondary key-store.
  Future<void> setEncryptionKeys(AtClient atClient, String atSign) async {
    // Check if the encryption keys are already for the atSign.
    // If yes, return; else set the encryption keys.
    String? encryptionPublicKey;
    try {
      encryptionPublicKey =
          await atClient.getLocalSecondary()?.getEncryptionPublicKey(atSign);
    } on KeyNotFoundException {
      _logger.info('Encryption keys are not found. Adding to the keystore.');
    }
    if (encryptionPublicKey.isNotNull && encryptionPublicKey != 'data:null') {
      _logger.info(
          'The encryption keys are already updated to keystore, returning');
      return;
    }
    bool result;
    // Set encryption private key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionPrivateKey,
        at_demo_data.encryptionPrivateKeyMap[atSign]!);
    if (result) {
      _logger.info('encryption private key was set successfully');
    } else {
      _logger.severe('failed to set encryption private key');
    }
    // set encryption public key. this key should be synced to the remote secondary
    var encryptionPublicKeyAtKey =
        '${AtConstants.atEncryptionPublicKey}$atSign';
    result = await atClient.getLocalSecondary()!.putValue(
        encryptionPublicKeyAtKey, at_demo_data.encryptionPublicKeyMap[atSign]!);
    if (result) {
      _logger.info('encryption public key was set successfully.');
    } else {
      _logger.info('failed to set encryption public key');
    }

    // set self encryption key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionSelfKey, at_demo_data.cramKeyMap[atSign]!);
    if (result) {
      _logger.info('self encryption key was set successfully');
    } else {
      _logger.severe('failed to set self encryption key');
    }
  }

  AtChops createAtChopsFromDemoKeys(String atSign) {
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        at_demo_data.encryptionPublicKeyMap[atSign]!,
        at_demo_data.encryptionPrivateKeyMap[atSign]!);
    var atPkamKeyPair = AtPkamKeyPair.create(
        at_demo_data.pkamPublicKeyMap[atSign]!,
        at_demo_data.pkamPrivateKeyMap[atSign]!);
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey = AESKey(at_demo_data.cramKeyMap[atSign]!);
    return AtChopsImpl(atChopsKeys);
  }
}
