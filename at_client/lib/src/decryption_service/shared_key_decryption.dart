import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

/// Class responsible for decrypting the value of shared key's that are not owned
/// by currentAtSign
/// Example:
/// CurrentAtSign: @bob
/// lookup:phone@alice
class SharedKeyDecryption implements AtKeyDecryption {
  final _logger = AtSignLogger('SharedKeyDecryption');

  @override
  Future decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null || encryptedValue.isEmpty) {
      throw IllegalArgumentException(
          'Decryption failed. Encrypted value is null');
    }
    String? encryptedSharedKey;
    if (atKey.metadata != null && atKey.metadata!.pubKeyCS != null) {
      encryptedSharedKey = atKey.metadata!.sharedKeyEnc;
      final atClient = AtClientManager.getInstance().atClient;
      final currentAtSignPublicKey = (await atClient
              .getLocalSecondary()!
              .getEncryptionPublicKey(atClient.getCurrentAtSign()!))
          ?.trim();
      if (currentAtSignPublicKey != null &&
          atKey.metadata!.pubKeyCS !=
              EncryptionUtil.md5CheckSum(currentAtSignPublicKey)) {
        throw AtClientException(error_codes['AtClientException'],
            'Public key has changed. Cannot decrypt shared data- ${atKey.key}');
      }
    } else {
      encryptedSharedKey = await _getEncryptedSharedKey(atKey);
    }
    if (encryptedSharedKey == null ||
        encryptedSharedKey.isEmpty ||
        encryptedSharedKey == 'null') {
      throw KeyNotFoundException('shared encryption key not found');
    }
    var currentAtSignPrivateKey = await (AtClientManager.getInstance()
        .atClient
        .getLocalSecondary()!
        .getEncryptionPrivateKey());
    if (currentAtSignPrivateKey == null || currentAtSignPrivateKey.isEmpty) {
      throw KeyNotFoundException('encryption private not found');
    }
    return EncryptionUtil.decryptValue(encryptedValue,
        EncryptionUtil.decryptKey(encryptedSharedKey, currentAtSignPrivateKey));
  }

  Future<String> _getEncryptedSharedKey(AtKey atKey) async {
    String? encryptedSharedKey = '';
    var localLookupSharedKeyBuilder = LLookupVerbBuilder()
      ..atKey = AT_ENCRYPTION_SHARED_KEY
      ..sharedWith = AtClientManager.getInstance().atClient.getCurrentAtSign()
      ..sharedBy = atKey.sharedBy
      ..isCached = true;
    try {
      encryptedSharedKey = await AtClientManager.getInstance()
          .atClient
          .getLocalSecondary()!
          .executeVerb(localLookupSharedKeyBuilder);
    } on KeyNotFoundException {
      _logger.finer(
          '${atKey.sharedBy}:${localLookupSharedKeyBuilder.atKey}@${atKey.sharedWith} not found in local secondary. Fetching from cloud secondary');
    }
    if (encryptedSharedKey == null ||
        encryptedSharedKey.isEmpty ||
        encryptedSharedKey == 'data:null') {
      var sharedKeyLookUpBuilder = LookupVerbBuilder()
        ..atKey = AT_ENCRYPTION_SHARED_KEY
        ..sharedBy = atKey.sharedBy
        ..auth = true;
      encryptedSharedKey = await AtClientManager.getInstance()
          .atClient
          .getRemoteSecondary()!
          .executeAndParse(sharedKeyLookUpBuilder);
    }
    if (encryptedSharedKey.isNotEmpty) {
      return DefaultResponseParser().parse(encryptedSharedKey).response;
    }
    return encryptedSharedKey;
  }
}
