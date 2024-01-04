import 'package:at_client/at_client.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';

/// Class responsible for decrypting the value of self key's
/// Example:
/// CurrentAtSign: @bob and
/// llookup:phone.wavi@bob
/// llookup:@bob:phone@bob
class SelfKeyDecryption implements AtKeyDecryption {
  final AtClient _atClient;
  late final AtSignLogger _logger;
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

    var selfEncryptionKey =
        await _atClient.getLocalSecondary()!.getEncryptionSelfKey();
    if ((selfEncryptionKey == null || selfEncryptionKey.isEmpty) ||
        selfEncryptionKey == 'data:null') {
      throw SelfKeyNotFoundException('Empty or null SelfEncryptionKey found',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
    }

    InitialisationVector iV;
    if (atKey.metadata.ivNonce != null) {
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
    } else {
      iV = AtChopsUtil.generateIVLegacy();
    }
    AtEncryptionResult decryptionResultFromAtChops;
    try {
      var encryptionAlgo = AESEncryptionAlgo(
          AESKey(DefaultResponseParser().parse(selfEncryptionKey).response));
      decryptionResultFromAtChops = _atClient.atChops!.decryptString(
          encryptedValue, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptionResultFromAtChops.result;
  }
}
