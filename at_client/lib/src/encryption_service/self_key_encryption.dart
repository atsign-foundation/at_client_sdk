import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

///Class responsible for encrypting the selfKey's
class SelfKeyEncryption implements AtKeyEncryption {
  final _logger = AtSignLogger('SelfKeyEncryption');

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! String) {
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }
    try {
      // Get AES key for current atSign
      var selfEncryptionKey = await _getSelfEncryptionKey();
      if (selfEncryptionKey == null ||
          selfEncryptionKey.isEmpty ||
          selfEncryptionKey == 'data:null') {
        throw KeyNotFoundException(
            'Self encryption key is not set for atSign ${atKey.sharedBy}');
      }
      selfEncryptionKey =
          DefaultResponseParser().parse(selfEncryptionKey).response;
      // Encrypt value using sharedKey
      return EncryptionUtil.encryptValue(value, selfEncryptionKey);
    } on Exception catch (e) {
      _logger.severe(
          'Exception while encrypting value for key ${atKey.key}: ${e.toString()}');
    }
  }

  Future<String?> _getSelfEncryptionKey() async {
    return AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .getEncryptionSelfKey();
  }
}
