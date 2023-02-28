abstract class PkamKeySource {
  String getPublicKey();
}

class AtKeysPkamKeySource implements PkamKeySource {
  final String _publicKey;

  AtKeysPkamKeySource(this._publicKey);

  @override
  String getPublicKey() {
    return _publicKey;
  }
}

class SecureElementPkamKeySource implements PkamKeySource {
  final String _publicKey;

  SecureElementPkamKeySource(this._publicKey);

  @override
  String getPublicKey() {
    return _publicKey;
  }
}

class AtKeysFileData {
  String _jsonData;
  String _decryptionKey;
  AtKeysFileData(this._jsonData, this._decryptionKey);
}
