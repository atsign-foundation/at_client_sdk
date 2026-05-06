import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';

class CipherScheme extends CryptoScheme {
  @override
  Future<dynamic> decrypt(AtKey atKey, value) async {
    return value.toString().substring(3);
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, value) async {
    return 'abc$value';
  }

  @override
  Future<void> register() async {
    return;
  }
}

class ErrorScheme extends CryptoScheme {
  @override
  Future<dynamic> decrypt(AtKey atKey, value) {
    throw AtDecryptionException('error');
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, value) {
    throw AtEncryptionException('error');
  }

  @override
  Future<void> register() {
    throw UnimplementedError();
  }
}
