import 'package:at_client/at_client.dart';

class CipherProvider extends CryptoProvider {
  @override
  final String id;

  CipherProvider([this.id = 'cipher-provider']);

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    return CryptoDecryptResult(
      plaintext: request.ciphertext.toString().substring(3),
    );
  }

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    // Mirrors the contract real providers follow: populate sharedKeyEnc on
    // encrypt so notification tests can assert metadata was forwarded.
    request.atKey.metadata.sharedKeyEnc = 'sharedKeyEnc';
    return CryptoEncryptResult(
      ciphertext: 'abc${request.plaintext}',
      metadata: AppMetadata(id),
    );
  }
}

class ErrorProvider extends CryptoProvider {
  @override
  final String id;

  ErrorProvider([this.id = 'error-provider']);

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) {
    throw AtDecryptionException('error');
  }

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) {
    throw AtEncryptionException('error');
  }
}
