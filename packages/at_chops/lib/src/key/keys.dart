/// Represents abstract format all keys should be in.
sealed class AbstractKey {
  final String _key;
  AbstractKey(this._key);
}

/// Represent a key for symmetric key encryption/decryption
class SymmetricKey extends AbstractKey {
  SymmetricKey(super._key);
  String get key => _key;
}

/// Represents a private key from [AtKeyPair]
class AtPrivateKey extends AbstractKey {
  AtPrivateKey.fromString(super._key);
  String get privateKey => _key;
}

/// Represents a public key from [AtKeyPair]
class AtPublicKey extends AbstractKey {
  AtPublicKey.fromString(super._key);
  String get publicKey => _key;
}

/// Represents abstract format of a keyPair
sealed class AbstractKeyPair {
  final AtPrivateKey _atPrivateKey;
  final AtPublicKey _atPublicKey;
  AbstractKeyPair(this._atPublicKey, this._atPrivateKey);

  AtPublicKey get atPublicKey => _atPublicKey;
  AtPrivateKey get atPrivateKey => _atPrivateKey;
}

/// Represents an AsymmetricKeyPair format
abstract class AsymmetricKeyPair extends AbstractKeyPair {
  AsymmetricKeyPair.create(String publicKey, String privateKey)
      : super(AtPublicKey.fromString(publicKey),
            AtPrivateKey.fromString(privateKey));
}
