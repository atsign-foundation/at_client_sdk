import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_utils/at_logger.dart';

///Class responsible for encrypting the selfKey's
class SelfKeyEncryption implements AtKeyEncryption {
  late final AtSignLogger _logger;

  final AtClient _atClient;

  SelfKeyEncryption(this._atClient) {
    _logger =
        AtSignLogger('SelfKeyEncryption (${_atClient.getCurrentAtSign()})');
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
        await _getSelfEncryptionKey(_atClient.getLocalSecondary()!);
    selfEncryptionKey =
        DefaultResponseParser().parse(selfEncryptionKey).response;
    AtEncryptionResult encryptionResultFromAtChops;
    try {
      InitialisationVector iV;
      if (atKey.metadata.ivNonce != null) {
        iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      } else {
        iV = AtChopsUtil.generateIVLegacy();
      }
      var encryptionAlgo = AESEncryptionAlgo(AESKey(selfEncryptionKey));
      encryptionResultFromAtChops = _atClient.atChops!.encryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtEncryptionException catch (e) {
      _logger.severe(
          'encryption exception during self encryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return encryptionResultFromAtChops.result;
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
