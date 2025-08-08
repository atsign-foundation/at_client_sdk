/// Represents a key for Challenge Response Authentication
class CramKey {
  final String _cramSecret;
  CramKey(this._cramSecret);
  String get secret => _cramSecret;
}
