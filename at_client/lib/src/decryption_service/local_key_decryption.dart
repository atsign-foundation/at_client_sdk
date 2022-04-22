import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of key shared to other atSign's
/// Example of local keys:
/// CurrentAtSign: @bob
/// llookup:@alice:phone@bob
class LocalKeyDecryption implements AtKeyDecryption {
  final _logger = AtSignLogger('LocalKeyDecryption');

  @override
  Future<String> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    // Get the shared key.
    var sharedKey = await AbstractAtKeyEncryption.getSharedKey(atKey);

    if (sharedKey.isEmpty) {
      _logger.severe('Decryption failed. SharedKey is null');
      throw KeyNotFoundException('Decryption failed. SharedKey is null');
    }
    return EncryptionUtil.decryptValue(encryptedValue, sharedKey);
  }
}
