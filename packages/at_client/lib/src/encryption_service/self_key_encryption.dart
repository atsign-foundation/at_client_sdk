import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

///Class responsible for encrypting the selfKey's
class SelfKeyEncryption implements AtKeyEncryption {
  late final AtSignLogger _logger;

  final AtClient atClient;

  SelfKeyEncryption(this.atClient) {
    _logger =
        AtSignLogger('SelfKeyEncryption (${atClient.getCurrentAtSign()})');
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value,
      {bool storeSharedKeyEncryptedWithData = true}) async {
    if (value is! String) {
      _logger.severe(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }
    // Get AES key for current atSign
    var selfEncryptionKey =
        atClient.atChops?.atChopsKeys.selfEncryptionKey?.key;
    // Encrypt value using sharedKey
    return EncryptionUtil.encryptValue(value, selfEncryptionKey!,
        ivBase64: atKey.metadata?.ivNonce);
  }
}
