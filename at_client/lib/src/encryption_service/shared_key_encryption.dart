import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';

///Class responsible for encrypting the value of the SharedKey's
class SharedKeyEncryption extends AbstractAtKeyEncryption {
  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! String) {
      throw AtValueException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String')
        ..contextParams = (ContextParams()
          ..exceptionScenario = ExceptionScenario.invalidValueProvided);
    }
    await super.encrypt(atKey, value);
    // Encrypt value using sharedKey
    return EncryptionUtil.encryptValue(value, sharedKey);
  }
}
