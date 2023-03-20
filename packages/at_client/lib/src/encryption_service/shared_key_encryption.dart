import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';

///Class responsible for encrypting the value of the SharedKey's
class SharedKeyEncryption extends AbstractAtKeyEncryption {
  SharedKeyEncryption(AtClient atClient) : super(atClient);

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! String) {
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }
    await super.encrypt(atKey, value);
    // Encrypt value using sharedKey
    return EncryptionUtil.encryptValue(value, sharedKey, ivBase64: atKey.metadata?.ivNonce);
  }
}
