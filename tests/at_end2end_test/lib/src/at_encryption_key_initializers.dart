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
  static final _logger = AtSignLogger('AtEncryptionKeysLoader');

  static final AtEncryptionKeysLoader _singleton =
      AtEncryptionKeysLoader._internal();

  AtEncryptionKeysLoader._internal();

  factory AtEncryptionKeysLoader.getInstance() {
    return _singleton;
  }

  /// Stores [atSign]'s credentials, as `AtCredentials` holds them, in the
  /// local secondary key-store.
  Future<void> setEncryptionKeys(AtClient atClient, String atSign) async {
    final credentials = AtCredentials.credentialsMap[atSign]!;
    bool result;

    // Set encryption private key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionPrivateKey,
        credentials[TestConstants.ENCRYPTION_PRIVATE_KEY].toString());
    if (result) {
      _logger.finer('encryption private key was set successfully');
    } else {
      _logger.severe('failed to set encryption private key');
    }

    // set encryption public key. this key should be synced to the remote secondary
    var encryptionPublicKeyAtKey =
        '${AtConstants.atEncryptionPublicKey}$atSign';
    result = await atClient.getLocalSecondary()!.putValue(
        encryptionPublicKeyAtKey,
        credentials[TestConstants.ENCRYPTION_PUBLIC_KEY].toString());
    if (result) {
      _logger.finer('encryption public key was set successfully.');
    } else {
      _logger.severe('failed to set encryption public key');
    }

    // set self encryption key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionSelfKey,
        credentials[TestConstants.SELF_ENCRYPTION_KEY].toString());
    if (result) {
      _logger.finer('self encryption key was set successfully');
    } else {
      _logger.severe('failed to set self encryption key');
    }

    // set the PKAM pair. A client built with no key source reads it from
    // the keystore, and cannot sign without these.
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atPkamPublicKey,
        credentials[TestConstants.PKAM_PUBLIC_KEY].toString());
    result = result &&
        await atClient.getLocalSecondary()!.putValue(
            AtConstants.atPkamPrivateKey,
            credentials[TestConstants.PKAM_PRIVATE_KEY].toString());
    if (result) {
      _logger.finer('pkam key pair was set successfully');
    } else {
      _logger.severe('failed to set the pkam key pair');
    }
  }
}
