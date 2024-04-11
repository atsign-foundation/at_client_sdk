import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of self key's
/// Example:
/// CurrentAtSign: @bob and
/// llookup:phone.wavi@bob
/// llookup:@bob:phone@bob
class SelfKeyDecryption implements AtKeyDecryption {
  late final AtSignLogger _logger;

  final AtClient _atClient;

  SelfKeyDecryption(this._atClient) {
    _logger =
        AtSignLogger('SelfKeyDecryption (${_atClient.getCurrentAtSign()})');
  }

  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null ||
        encryptedValue.isEmpty ||
        encryptedValue == 'null') {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }

    // Get SelfEncryptionKey from atChops
    // To support backward compatibility of at_client_mobile, if SelfEncryptionKey is null in atChops,
    // fetch from LocalSecondary and set it to AtChops Instance.
    String? selfEncryptionKey =
        _atClient.atChops?.atChopsKeys.selfEncryptionKey?.key;
    if (selfEncryptionKey.isNullOrEmpty) {
      // Fetch Self Encryption Key from Local Secondary
      // Remove this call after the atChops has self encryption key populated from AtClientMobile.
      selfEncryptionKey =
          await _atClient.getLocalSecondary()!.getEncryptionSelfKey();
    }
    // If selfEncryptionKey is null in atChops and in Local Secondary throw exception.
    if (selfEncryptionKey.isNullOrEmpty) {
      throw SelfKeyNotFoundException(
          'Failed to decrypt the key: ${atKey.toString()} caused by self encryption key not found',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }
    // If SelfEncryptionKey is found in local secondary, set it to AtChops instance.
    _atClient.atChops?.atChopsKeys.selfEncryptionKey =
        AESKey(selfEncryptionKey!);

    InitialisationVector iV;
    if (atKey.metadata.ivNonce != null) {
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
    } else {
      iV = AtChopsUtil.generateIVLegacy();
    }
    AtEncryptionResult decryptionResultFromAtChops;
    try {
      var encryptionAlgo = AESEncryptionAlgo(
          AESKey(DefaultResponseParser().parse(selfEncryptionKey!).response));
      decryptionResultFromAtChops = _atClient.atChops!.decryptString(
          encryptedValue, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during decryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptionResultFromAtChops.result;
  }
}
