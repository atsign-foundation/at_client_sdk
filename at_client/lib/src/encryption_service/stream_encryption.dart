import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_commons/at_commons.dart';

/// Class responsible for encrypting the stream data.
class StreamEncryption extends AbstractAtKeyEncryption {
  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! List<int>) {
      throw AtClientException(atClientErrorCodes['AtClientException'],
          'Invalid value type found: ${value.runtimeType}. Valid value type is List<int>');
    }

    await super.encrypt(atKey, value);

    // Encrypt value using sharedKey
    var encryptedValue = EncryptionUtil.encryptBytes(value, sharedKey);
    return encryptedValue;
  }
}
