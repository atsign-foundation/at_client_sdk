import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of key shared to other atSign's
/// Example of local keys:
/// CurrentAtSign: @bob
/// llookup:@alice:phone@bob
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
        .getLocalSecondary()!
        .getEncryptionPrivateKey();

    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey =
          '$AT_ENCRYPTION_SHARED_KEY.${atKey.sharedWith?.replaceAll('@', '')}'
      ..sharedBy = AtClientManager.getInstance().atClient.getCurrentAtSign();
    var sharedKey = await AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .executeVerb(llookupVerbBuilder);

    if (sharedKey == null || sharedKey.isEmpty) {
      _logger.severe('Decryption failed. SharedKey is null');
      throw KeyNotFoundException('Decryption failed. SharedKey is null');
    }
    sharedKey = DefaultResponseParser().parse(sharedKey).response;
    return EncryptionUtil.decryptValue(encryptedValue,
        EncryptionUtil.decryptKey(sharedKey, currentAtSignPrivateKey!));
  }
}
