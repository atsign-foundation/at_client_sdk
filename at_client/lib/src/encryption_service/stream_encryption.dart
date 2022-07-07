import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';

/// Class responsible for encrypting the stream data.
class StreamEncryption extends AbstractAtKeyEncryption {
  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! List<int>) {
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is List<int>');
    }
    await super.encrypt(atKey, value);
    // Encrypt value using sharedKey
    return EncryptionUtil.encryptBytes(value, sharedKey);
  }
}
