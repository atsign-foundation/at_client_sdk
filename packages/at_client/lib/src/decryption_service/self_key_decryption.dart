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

  SelfKeyDecryption(this._atClient);

  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null ||
        encryptedValue.isEmpty ||
        encryptedValue == 'null') {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }

    if (_atClient.atChops == null ||
        _atClient.atChops!.atChopsKeys.selfEncryptionKey == null) {
      throw SelfKeyNotFoundException(
          'Failed to decrypt the key: ${atKey.toString()} caused by self encryption key not found');
    }

    var selfEncryptionKey =
        _atClient.atChops!.atChopsKeys.selfEncryptionKey!.key;
    return EncryptionUtil.decryptValue(encryptedValue,
        DefaultResponseParser().parse(selfEncryptionKey).response,
        ivBase64: atKey.metadata?.ivNonce);
  }
}
