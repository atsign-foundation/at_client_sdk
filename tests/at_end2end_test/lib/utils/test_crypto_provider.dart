import 'package:at_client/at_client.dart';

/// for testing only,
/// decrypt() returns 'twin'
/// encrypt() returns 'hellohello'
class TestCryptoProvider extends CryptoProvider {
  @override
  final String id;

  TestCryptoProvider(this.id);

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    return const CryptoDecryptResult(plaintext: 'twin');
  }

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    return CryptoEncryptResult(
      ciphertext: 'hellohello',
      metadata: AppMetadata(id),
    );
  }
}
