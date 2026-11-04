import 'package:at_chops/src/key/keys.dart';
import 'package:crypton/crypton.dart';

class RsaKeyPair extends AsymmetricKeyPair {
  RsaKeyPair.create(super.publicKey, super.privateKey) : super.create();

  /// Generates RSA keypair with default size 2048 bits
  static RsaKeyPair generate({int keySize = 2048}) {
    RSAKeypair rkp = RSAKeypair.fromRandom(keySize: keySize);
    return RsaKeyPair.create(
      rkp.publicKey.toString(),
      rkp.privateKey.toString(),
    );
  }
}
