import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

///Class responsible for encrypting the selfKey's
class SelfKeyEncryption implements AtKeyEncryption {
  late final AtSignLogger _logger;

  final AtClient atClient;

  SelfKeyEncryption(this.atClient) {
    _logger =
        AtSignLogger('SelfKeyEncryption (${atClient.getCurrentAtSign()})');
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value,
      {bool storeSharedKeyEncryptedWithData = true}) async {
    if (value is! String) {
      _logger.severe(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }

    if (atClient.atChops == null ||
        atClient.atChops!.atChopsKeys.selfEncryptionKey == null) {
      throw SelfKeyNotFoundException(
          'Failed to encrypt the data caused by Self encryption key not found');
    }
    // Get AES key for current atSign
    var selfEncryptionKey =
        atClient.atChops?.atChopsKeys.selfEncryptionKey?.key;

    AtEncryptionResult encryptionResultFromAtChops;
    try {
      InitialisationVector iV;
      if (atKey.metadata.ivNonce != null) {
        iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      } else {
        iV = AtChopsUtil.generateIVLegacy();
      }
      var encryptionAlgo = AESEncryptionAlgo(AESKey(selfEncryptionKey!));
      encryptionResultFromAtChops = atClient.atChops!.encryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtEncryptionException catch (e) {
      _logger.severe(
          'encryption exception during self encryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return encryptionResultFromAtChops.result;
  }
}
