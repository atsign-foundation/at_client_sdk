import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

import '../client/at_client_spec.dart';
import '../util/encryption_util.dart';

class CryptoUtil {
  static Future<void> validatePublicKey(AtKey atKey, AtClient atClient) async {
    String? currentAtSignPublicKey;
    try {
      currentAtSignPublicKey = (await atClient
              .getLocalSecondary()!
              .getEncryptionPublicKey(atClient.getCurrentAtSign()!))
          ?.trim();
    } on KeyNotFoundException {
      throw AtPublicKeyNotFoundException(
          'Failed to fetch the current atSign public key - public:publickey${atClient.getCurrentAtSign()!}',
          intent: Intent.fetchEncryptionPublicKey,
          exceptionScenario: ExceptionScenario.localVerbExecutionFailed);
    }
    if (currentAtSignPublicKey.isNullOrEmpty) {
      throw AtPublicKeyNotFoundException('Public key cannot be null or empty');
    }

    final isPubKeyHashMismatch = atKey.metadata.pubKeyHash != null &&
        atKey.metadata.pubKeyHash?.hash !=
            AtChops.hashWith(HashingAlgoType.fromString(
                    atKey.metadata.pubKeyHash!.hashingAlgo))
                .hash(currentAtSignPublicKey!.codeUnits);

    final isPubKeyCSMismatch = atKey.metadata.pubKeyCS != null &&
        atKey.metadata.pubKeyCS !=
            EncryptionUtil.md5CheckSum(currentAtSignPublicKey!);

    if (isPubKeyHashMismatch || isPubKeyCSMismatch) {
      throw AtPublicKeyChangeException(
        'Public key has changed. Cannot decrypt shared key ${atKey.toString()}',
        intent: Intent.fetchEncryptionPublicKey,
        exceptionScenario: ExceptionScenario.decryptionFailed,
      );
    }
  }
}
