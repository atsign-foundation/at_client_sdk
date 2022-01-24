import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

///Class responsible for encrypting the selfKey's
class SelfKeyEncryption implements AtKeyEncryption {
  final _logger = AtSignLogger('SelfKeyEncryption');

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! String) {
      throw AtClientException(atClientErrorCodes['AtClientException'],
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }
    try {
      // Get AES key for current atSign
      var selfEncryptionKey = await _getSelfEncryptionKey();
      if (selfEncryptionKey.isEmpty || selfEncryptionKey == 'data:null') {
        throw KeyNotFoundException(
            'Self encryption key is not set for atSign ${atKey.sharedBy}');
      }
      selfEncryptionKey =
          DefaultResponseParser().parse(selfEncryptionKey).response;
      // Encrypt value using sharedKey
      var encryptedValue =
          EncryptionUtil.encryptValue(value, selfEncryptionKey);
      return encryptedValue;
    } on Exception catch (e) {
      _logger.severe(
          'Exception while encrypting value for key ${atKey.key}: ${e.toString()}');
      return '';
    }
  }

  Future<String> _getSelfEncryptionKey() async {
    var selfEncryptionKey = await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .getEncryptionSelfKey();
    return selfEncryptionKey;
  }
}
