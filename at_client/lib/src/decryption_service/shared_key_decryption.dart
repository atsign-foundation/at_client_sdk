import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of shared key's that are not owned
/// by currentAtSign
/// Example:
/// CurrentAtSign: @bob
/// lookup:phone@alice.
class SharedKeyDecryption implements AtKeyDecryption {
  final _logger = AtSignLogger('SharedKeyDecryption');

  @override
  Future decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue.isEmpty) {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    String encryptedSharedKey = await _getEncryptedSharedKey(atKey);
    if (encryptedSharedKey.isEmpty || encryptedSharedKey == 'null') {
      throw KeyNotFoundException('encrypted Shared key not found');
    }
    var currentAtSignPrivateKey = await (AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()
        .getEncryptionPrivateKey());
    if (currentAtSignPrivateKey.isEmpty) {
      throw KeyNotFoundException('encryption private not found');
    }
    var sharedKey =
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey);

    //3. decrypt value using shared key
    var decryptedValue = EncryptionUtil.decryptValue(encryptedValue, sharedKey);
    return decryptedValue;
  }

  Future<String> _getEncryptedSharedKey(AtKey atKey) async {
    String encryptedSharedKey = '';
    var metadata = Metadata()..isCached = true;
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = AT_ENCRYPTION_SHARED_KEY
        ..sharedWith = AtClientManager.getInstance().atClient.getCurrentAtSign()
        ..sharedBy = atKey.sharedBy
        ..metadata = metadata);
    try {
      encryptedSharedKey = await AtClientManager.getInstance()
          .atClient
          .getLocalSecondary()
          .executeVerb(localLookupSharedKeyBuilder);
    } on KeyNotFoundException {
      _logger.finer(
          '${atKey.sharedBy}:${localLookupSharedKeyBuilder.atKey}@${atKey.sharedWith} not found in local secondary. Fetching from cloud secondary');
    }
    if (encryptedSharedKey == 'data:null') {
      var sharedKeyLookUpBuilder = LookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = AT_ENCRYPTION_SHARED_KEY
          ..sharedBy = atKey.sharedBy)
        ..auth = true;
      encryptedSharedKey = await AtClientManager.getInstance()
          .atClient
          .getRemoteSecondary()
          .executeAndParse(sharedKeyLookUpBuilder);
    }
    if (encryptedSharedKey.isNotEmpty) {
      encryptedSharedKey = encryptedSharedKey.replaceFirst('data:', '');
    }
    return encryptedSharedKey;
  }
}
