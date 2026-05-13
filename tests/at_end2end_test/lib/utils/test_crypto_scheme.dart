import 'package:at_client/at_client.dart';

/// for testing only,
/// decrypt() returns 'twin'
/// encrypt() returns 'hellohello'
class TestCryptoScheme extends CryptoScheme {
  @override
  Future<dynamic> decrypt(AtKey atKey, value) async {
    return 'twin';
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, value) async {
    return 'hellohello';
  }

  @override
  Future<void> register() async {
    return;
  }
}
