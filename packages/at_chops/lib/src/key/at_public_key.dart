/// Represents a public key from [AtKeyPair]
class AtPublicKey {
  final String _publicKey;
  AtPublicKey.fromString(this._publicKey);
  String get publicKey => _publicKey;
}
