import 'package:at_client/at_client.dart';

class CipherProvider extends CryptoProvider {
  @override
  final String id;

  CipherProvider([this.id = 'cipher-provider']);

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    return value.substring(3);
  }

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    // Mirrors the contract real providers follow: stamp routing metadata on
    // encrypt so notification tests can assert metadata was forwarded, and set
    // sharedKeyEnc so the metadata-forwarding assertions still hold.
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    atKey.metadata.sharedKeyEnc = 'sharedKeyEnc';
    return 'abc$value';
  }
}

/// Decrypt always throws [FormatException] — models a provider handed
/// plaintext (not valid base64), so the get path's legacy try-decrypt
/// fallback can be exercised.
class FormatExceptionProvider extends CryptoProvider {
  @override
  final String id;

  FormatExceptionProvider([this.id = 'format-exception-provider']);

  @override
  Future<String> decrypt(CryptoContext context, AtKey atKey, String value) {
    throw const FormatException('not base64');
  }

  @override
  Future<String> encrypt(CryptoContext context, AtKey atKey, String value) {
    throw AtEncryptionException('error');
  }
}

class ErrorProvider extends CryptoProvider {
  @override
  final String id;

  ErrorProvider([this.id = 'error-provider']);

  @override
  Future<String> decrypt(CryptoContext context, AtKey atKey, String value) {
    throw AtDecryptionException('error');
  }

  @override
  Future<String> encrypt(CryptoContext context, AtKey atKey, String value) {
    throw AtEncryptionException('error');
  }
}
