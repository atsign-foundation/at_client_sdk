import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of key shared to other atSign's
/// Example of local keys:
/// CurrentAtSign: @bob
/// llookup:@alice:phone@bob
class LocalKeyDecryption extends AbstractAtKeyEncryption
    implements AtKeyDecryption {
  late final AtSignLogger _logger;

  LocalKeyDecryption(AtClient atClient) : super(atClient) {
    _logger =
        AtSignLogger('LocalKeyDecryption (${atClient.getCurrentAtSign()})');
  }

  @override
  Future<String> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }
    // Get the shared key.
    var sharedKey = await getSharedKey(atKey);

    if (sharedKey.isEmpty) {
      _logger.severe('Decryption failed. SharedKey is null');
      throw SharedKeyNotFoundException('Empty or null SharedKey is found',
          intent: Intent.fetchEncryptionSharedKey,
          exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
    }
    return EncryptionUtil.decryptValue(encryptedValue, sharedKey, ivBase64: atKey.metadata?.ivNonce);
  }
}
