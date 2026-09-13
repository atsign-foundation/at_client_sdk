// The flat keyfile fields are the legacy document's, which is the shape the
// demo atSigns' credentials take.
// ignore_for_file: deprecated_member_use

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_utils/at_logger.dart';

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
    bool result;
    // Set encryption private key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionPrivateKey, encryptionPrivateKeyMap[atSign]!);
    if (result) {
      _logger.info('encryption private key was set successfully');
    } else {
      _logger.severe('failed to set encryption private key');
    }
    // set encryption public key. this key should be synced to the remote secondary
    var encryptionPublicKeyAtKey =
        '${AtConstants.atEncryptionPublicKey}$atSign';
    result = await atClient
        .getLocalSecondary()!
        .putValue(encryptionPublicKeyAtKey, encryptionPublicKeyMap[atSign]!);
    if (result) {
      _logger.info('encryption public key was set successfully.');
    } else {
      _logger.info('failed to set encryption public key');
    }

    // set self encryption key
    result = await atClient
        .getLocalSecondary()!
        .putValue(AtConstants.atEncryptionSelfKey, aesKeyMap[atSign]!);
    if (result) {
      _logger.info('self encryption key was set successfully');
    } else {
      _logger.severe('failed to set self encryption key');
    }
    // set pkam keys
    result = await atClient
        .getLocalSecondary()!
        .putValue(AtConstants.atPkamPublicKey, pkamPublicKeyMap[atSign]!);
    if (result) {
      _logger.info('pkam public key was set successfully');
    } else {
      _logger.severe('failed to pkam public key');
    }

    result = await atClient
        .getLocalSecondary()!
        .putValue(AtConstants.atPkamPrivateKey, pkamPrivateKeyMap[atSign]!);
    if (result) {
      _logger.info('pkam private key was set successfully');
    } else {
      _logger.severe('failed to pkam private key');
    }
  }

  /// The demo atSign's credentials as a legacy keyfile: the flat fields,
  /// naming no enrollment, which is what the virtualenv's `pkamLoad`
  /// installed and what a keyfile from before enrollments holds.
  ///
  /// NOTE: flat, never typed. Active typed rsa2048 authentication material
  /// reads as a retrofit already done, so a client under a PQ posture would
  /// refuse to upgrade from it.
  AtKeys createAtKeysFromDemoKeys(String atSign) => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(pkamPublicKeyMap[atSign]!)
    ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKeyMap[atSign]!)
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(encryptionPublicKeyMap[atSign]!)
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(encryptionPrivateKeyMap[atSign]!)
    ..defaultSelfEncryptionKey = AtBytes.fromString(aesKeyMap[atSign]!);

  AtChops createAtChopsFromDemoKeys(String atSign) {
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!);
    var atPkamKeyPair = AtPkamKeyPair.create(
        pkamPublicKeyMap[atSign]!, pkamPrivateKeyMap[atSign]!);
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey = AESKey(aesKeyMap[atSign]!);
    return AtChopsImpl(atChopsKeys);
  }
}
