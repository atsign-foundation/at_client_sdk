import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

///Class responsible for encrypting the selfKey's
class SelfKeyEncryption implements AtKeyEncryption {
  late final AtSignLogger _logger;

  final AtClient atClient;

  SelfKeyEncryption(this.atClient) {
    _logger = AtSignLogger('SelfKeyEncryption (${atClient.getCurrentAtSign()})');
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async {
    if (value is! String) {
      _logger.severe(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }
    // Get AES key for current atSign
    var selfEncryptionKey = await _getSelfEncryptionKey(atClient.getLocalSecondary()!);
    selfEncryptionKey =
        DefaultResponseParser().parse(selfEncryptionKey).response;
    // Encrypt value using sharedKey
    return EncryptionUtil.encryptValue(value, selfEncryptionKey);
  }

  Future<String> _getSelfEncryptionKey(LocalSecondary localSecondary) async {
    String? selfEncryptionKey;
    try {
      selfEncryptionKey = await localSecondary.getEncryptionSelfKey();
      if (selfEncryptionKey.isNull) {
        _logger.severe('Found a null value for self encryption key');
        throw SelfKeyNotFoundException(
            'Self encryption key is not set for current atSign',
            intent: Intent.fetchSelfEncryptionKey,
            exceptionScenario: ExceptionScenario.encryptionFailed);
      }
    } on KeyNotFoundException {
      throw SelfKeyNotFoundException(
          'Self encryption key is not set for current atSign',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }
    return selfEncryptionKey!;
  }
}
