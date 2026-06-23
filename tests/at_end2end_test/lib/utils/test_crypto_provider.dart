import 'package:at_client/at_client.dart';

/// for testing only,
/// decrypt() returns 'twin'
/// encrypt() returns 'hellohello'
class TestCryptoProvider extends CryptoProvider {
  @override
  final String id;

  TestCryptoProvider(this.id);

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    return 'twin';
  }

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    return 'hellohello';
  }
}
