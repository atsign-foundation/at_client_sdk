import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of local keys
/// Example of local keys:
/// CurrentAtSign: @bob
/// llookup:@bob:phone@bob
/// llookup:@alice:phone@bob
/// llookup:phone@bob
class LocalKeyDecryption implements AtKeyDecryption {
  final _logger = AtSignLogger('SelfKeyDecryption');

  @override
  Future<String> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    var currentAtSignPrivateKey = await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()
        .getEncryptionPrivateKey();
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = AtClientManager.getInstance().atClient.getCurrentAtSign();
    var sharedKey = await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()
        .executeVerb(llookupVerbBuilder);
    if (sharedKey.isEmpty) {
      _logger.severe('Decryption failed. SharedKey is null');
      throw AtClientException('AT0014', 'Decryption failed. SharedKey is null');
    }
    sharedKey = sharedKey.replaceFirst('data:', '');
    var decryptedSharedKey =
        EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey);
    return EncryptionUtil.decryptValue(encryptedValue, decryptedSharedKey);
  }
}
