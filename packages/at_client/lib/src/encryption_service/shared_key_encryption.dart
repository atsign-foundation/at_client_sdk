import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/encryption_service/abstract_atkey_encryption.dart';

///Class responsible for encrypting the value of the SharedKey's
class SharedKeyEncryption extends AbstractAtKeyEncryption {
  final AtClient _atClient;
  late final AtSignLogger _logger;
  SharedKeyEncryption(this._atClient) : super(_atClient) {
    _logger =
        AtSignLogger('SelfKeyEncryption (${_atClient.getCurrentAtSign()})');
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value,
      {bool storeSharedKeyEncryptedWithData = true}) async {
    if (value is! String) {
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }

    // Call super.encrypt to take care of getting hold of the correct
    // encryption key and setting it in super.sharedKey
    await super.encrypt(atKey, value,
        storeSharedKeyEncryptedWithData: storeSharedKeyEncryptedWithData);
    AtEncryptionResult encryptionResultFromAtChops;
    try {
      InitialisationVector iV;
      if (atKey.metadata.ivNonce != null) {
        iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      } else {
        iV = AtChopsUtil.generateIVLegacy();
      }
      var encryptionAlgo = AESEncryptionAlgo(AESKey(sharedKey));
      encryptionResultFromAtChops = _atClient.atChops!.encryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtEncryptionException catch (e) {
      _logger.severe(
          'encryption exception during shared key encryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return encryptionResultFromAtChops.result;
  }
}