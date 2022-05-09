import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of self key's
/// Example:
/// CurrentAtSign: @bob and
/// llookup:phone.wavi@bob
/// llookup:@bob:phone@bob
class SelfKeyDecryption implements AtKeyDecryption {
  final _logger = AtSignLogger('SelfKeyDecryption');

  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null ||
        encryptedValue.isEmpty ||
        encryptedValue == 'null') {
      throw AtDecryptionException(
          'Decryption failed. Encrypted value is null');
    }

    var selfEncryptionKey = await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .getEncryptionSelfKey();
    if ((selfEncryptionKey == null || selfEncryptionKey.isEmpty) ||
        selfEncryptionKey == 'data:null') {
      throw KeyNotFoundException(
          'Decryption failed. SelfEncryptionKey not found');
    }

    return EncryptionUtil.decryptValue(encryptedValue,
        DefaultResponseParser().parse(selfEncryptionKey).response);
  }
}
