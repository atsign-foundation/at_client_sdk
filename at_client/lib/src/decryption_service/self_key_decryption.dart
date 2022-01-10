import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of self key's
/// Example:
/// CurrentAtSign: @bob and
/// llookup:_phone.wavi@bob
class SelfKeyDecryption implements AtKeyDecryption {
  final _logger = AtSignLogger('SelfKeyDecryption');

  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue == 'null') {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    if (!atKey.metadata!.isEncrypted) {
      _logger.info(
          'isEncrypted is set to false, Returning the original value without decrypting');
      return encryptedValue;
    }
    try {
      var selfEncryptionKey = await AtClientManager.getInstance()
          .atClient
          .getLocalSecondary()
          .getEncryptionSelfKey();
      if (selfEncryptionKey.isEmpty || selfEncryptionKey == 'data:null') {
        throw KeyNotFoundException(
            'Decryption failed. SelfEncryptionKey not found');
      }
      selfEncryptionKey = selfEncryptionKey.toString().replaceAll('data:', '');
      // decrypt value using self encryption key
      var decryptedValue =
          EncryptionUtil.decryptValue(encryptedValue, selfEncryptionKey);
      return decryptedValue;
    } on Error catch (e) {
      _logger.severe('Error while decrypting value: ${e.toString()}');
    }
  }
}
