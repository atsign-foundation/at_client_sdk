// The keyfile these helpers build is the flat legacy one, spelled through the
// at_chops compatibility types that describe it.
// ignore_for_file: deprecated_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// The flat keyfile fields for the keys in [atChopsKeys].
AtKeys getAtAuthKeysFromAtChopsKeys(AtChopsKeys atChopsKeys) {
  AtKeys atAuthKeys = AtKeys();

  if (atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.apkamPublicKey =
        AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.apkamPrivateKey =
        AtBytes.fromString(atChopsKeys.atPkamKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey != null) {
    atAuthKeys.defaultEncryptionPublicKey = AtBytes.fromString(
        atChopsKeys.atEncryptionKeyPair!.atPublicKey.publicKey);
  }
  if (atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey != null) {
    atAuthKeys.defaultEncryptionPrivateKey = AtBytes.fromString(
        atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey);
  }
  if (atChopsKeys.selfEncryptionKey?.key != null) {
    atAuthKeys.defaultSelfEncryptionKey =
        AtBytes.fromString(atChopsKeys.selfEncryptionKey!.key);
  }
  atAuthKeys.apkamSymmetricKey =
      AtBytes.fromString(atChopsKeys.apkamSymmetricKey!.key);

  return atAuthKeys;
}

/// A freshly minted RSA-2048 set: encryption and PKAM keypairs, with a
/// self-encryption and an APKAM symmetric key.
AtChopsKeys getRandomAtChopsKeys() {
  AtEncryptionKeyPair encryptionKeyPair =
      AtChopsUtil.generateAtEncryptionKeyPair();
  AtPkamKeyPair pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
  AtChopsKeys atChopsKeys = AtChopsKeys.create(encryptionKeyPair, pkamKeyPair);
  atChopsKeys.selfEncryptionKey =
      AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
  atChopsKeys.apkamSymmetricKey =
      AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

  return atChopsKeys;
}
