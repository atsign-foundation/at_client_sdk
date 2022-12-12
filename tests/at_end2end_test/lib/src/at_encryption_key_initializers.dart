import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import '../utils/test_constants.dart';
import 'at_credentials.dart';

/// The class is responsible for loading all the encryption of the atSign to the
/// local secondary keystore.
///
/// Setting the class as a singleton class because of multiple instances of the class
/// might cause the inconsistency on setting the encryption keys.
class AtEncryptionKeysLoader {
  /// The encryptionKeyMap holds the atSign and the boolean value that indicates
  /// if the encryption key are set for an atSign.
  final Map _encryptionKeysCheckerMap = <String, bool>{};
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
    if (_encryptionKeysCheckerMap.containsKey(atSign)) {
      _logger.info(
          'the encryption keys are already updated to keystore, returning');
      return;
    }
    bool result;
    // Set encryption private key
    result = await atClient.getLocalSecondary()!.putValue(
        AT_ENCRYPTION_PRIVATE_KEY,
        AtCredentials
            .credentialsMap[atSign]![TestConstants.ENCRYPTION_PRIVATE_KEY]);
    if (result) {
      _logger.info('encryption private key was set successfully');
    } else {
      _logger.severe('failed to set encryption private key');
    }
    // set encryption public key. this key should be synced to the remote secondary
    var encryptionPublicKey = '$AT_ENCRYPTION_PUBLIC_KEY$atSign';
    result = await atClient.getLocalSecondary()!.putValue(
        encryptionPublicKey,
        AtCredentials
            .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY]);
    if (result) {
      _logger.info('encryption public key was set successfully.');
    } else {
      _logger.info('failed to set encryption public key');
    }

    // set self encryption key
    result = await atClient.getLocalSecondary()!.putValue(
        AT_ENCRYPTION_SELF_KEY,
        AtCredentials
            .credentialsMap[atSign]![TestConstants.SELF_ENCRYPTION_KEY]);
    if (result) {
      _logger.info('self encryption key was set successfully');
    } else {
      _logger.severe('failed to set self encryption key');
    }
    // If all the keys are set successfully, set the atSign and the result to
    // the encryptionKeysMap to check if the encryption keys are already set of subsequent tests.
    _encryptionKeysCheckerMap.putIfAbsent(atSign, () => result);
  }
}
