import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';

///Class responsible for encrypting the value of the SharedKey's
class SharedKeyEncryption extends AbstractAtKeyEncryption {
  SharedKeyEncryption(AtClient atClient) : super(atClient);

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value,
      {bool storeSharedKeyEncryptedWithData = true}) async {
    if (value is! String) {
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }

    // Call super.encrypt to take care of getting hold of the correct
    // encryption key and setting it in super.sharedKey
    await super.encrypt(atKey, value,
        storeSharedKeyEncryptedWithData: storeSharedKeyEncryptedWithData);

    // Encrypt the value
    return EncryptionUtil.encryptValue(value, sharedKey,
        ivBase64: atKey.metadata?.ivNonce);
  }
}
