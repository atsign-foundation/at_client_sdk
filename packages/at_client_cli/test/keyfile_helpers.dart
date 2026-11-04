import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';

/// A freshly minted legacy keyfile: RSA-2048 encryption and APKAM keypairs,
/// with a self-encryption and an APKAM symmetric key, all in the flat
/// fields.
AtKeys randomLegacyKeys() {
  final encryption = RsaKeyPair.generate();
  final apkam = RsaKeyPair.generate();
  return AtKeys.legacy(
    apkamPublicKey: apkam.atPublicKey.publicKey,
    apkamPrivateKey: apkam.atPrivateKey.privateKey,
    apkamSymmetricKey: AESKey.generate(32).key,
    encryptionPublicKey: encryption.atPublicKey.publicKey,
    encryptionPrivateKey: encryption.atPrivateKey.privateKey,
    selfEncryptionKey: AESKey.generate(32).key,
  );
}
