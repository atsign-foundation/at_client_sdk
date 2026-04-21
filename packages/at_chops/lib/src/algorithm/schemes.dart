import 'package:at_chops/src/key/at_key_pair.dart';
import 'package:at_chops/src/key/impl/at_encryption_key_pair.dart';
import 'package:at_chops/src/key/key_names.dart';
import 'package:at_chops/src/key/key_type.dart';
import 'package:at_commons/at_commons.dart';

class AES256CryptoScheme extends CryptoScheme {
  String iv;
  AES256CryptoScheme(String keyName, String encKeyName, this.iv)
      : super(
          keyName,
          EncryptionKeyType.aes256.name,
          encKeyName,
        );
}

class RSA2048KeyPairCryptoScheme extends CryptoScheme {
  AsymmetricKeyPair keyPair;
  RSA2048KeyPairCryptoScheme(
    String keyName, {
    required String publicKey,
    required String privateKey,
  }) : super(
          keyName,
          EncryptionKeyType.rsa2048.name,
          KeyNames.rsa2048EncKey,
        ) {
    keyPair = AsymmetricKeyPair.create(publicKey, privateKey);
  }
}
