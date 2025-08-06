/// Represents a private key from [AtKeyPair]
class AtPrivateKey {
  final String _privateKey;
  AtPrivateKey.fromString(this._privateKey);
  String get privateKey => _privateKey;
}
