import 'package:at_chops/src/key/at_private_key.dart';
import 'package:at_chops/src/key/at_public_key.dart';

/// Represents a key pair for asymmetric public-private key encryption/decryption
abstract class AsymmetricKeyPair {
  late AtPrivateKey _atPrivateKey;

  late AtPublicKey _atPublicKey;

  AsymmetricKeyPair.create(String publicKey, String privateKey) {
    _atPublicKey = AtPublicKey.fromString(publicKey);
    _atPrivateKey = AtPrivateKey.fromString(privateKey);
  }

  AtPublicKey get atPublicKey => _atPublicKey;
  AtPrivateKey get atPrivateKey => _atPrivateKey;
}

/// Represent a key for symmetric key encryption/decryption
abstract class SymmetricKey {
  late String key;
  SymmetricKey(this.key);
}
