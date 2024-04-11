import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:encrypt/encrypt.dart';

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
    String? selfEncryptionKey;
    if (value is! String) {
      _logger.severe(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
      throw AtEncryptionException(
          'Invalid value type found: ${value.runtimeType}. Valid value type is String');
    }

    // Get SelfEncryptionKey from atChops
    // To support backward compatibility of at_client_mobile, if SelfEncryptionKey is null in atChops,
    // fetch from LocalSecondary and set it to AtChops Instance.
    selfEncryptionKey = atClient.atChops?.atChopsKeys.selfEncryptionKey?.key;
    if (selfEncryptionKey.isNullOrEmpty) {
      // Fetch Self Encryption Key from Local Secondary
      // Remove this call after the atChops has self encryption key populated from AtClientMobile.
      selfEncryptionKey =
          await _getSelfEncryptionKey(atClient.getLocalSecondary()!);
    }
    // If selfEncryptionKey is null in atChops and in Local Secondary throw exception.
    if (selfEncryptionKey.isNullOrEmpty) {
      throw SelfKeyNotFoundException(
          'Failed to encrypt the data caused by Self encryption key not found',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }
    // If SelfEncryptionKey is found in local secondary, set it to AtChops instance.
    atClient.atChops?.atChopsKeys.selfEncryptionKey =
        AESKey(selfEncryptionKey!);

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

  Future<String?> _getSelfEncryptionKey(LocalSecondary localSecondary) async {
    String? selfEncryptionKey;
    try {
      selfEncryptionKey = await localSecondary.getEncryptionSelfKey();
    } on KeyNotFoundException {
      throw SelfKeyNotFoundException(
          'Self encryption key is not set for current atSign',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.encryptionFailed);
    }
    return selfEncryptionKey;
  }
}
