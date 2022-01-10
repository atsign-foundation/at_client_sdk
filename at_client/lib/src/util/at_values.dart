import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/signin_public_data.dart';
import 'package:at_commons/at_commons.dart';

/// Class responsible for transforming the request and response.
/// Encodes and encrypts the request.
/// Decodes and decrypts the response.
class AtValues {
  ///Accepts the [AtKey] and value and transforms the value based on type of [AtKey]
  /// If value is binary, encodes the value
  /// If AtKey is public, sign's data and with encryptionPrivateKey and places the
  /// signed data into [AtKey.metadata.dataSignature]
  /// If AtKey is not public, encrypts the value and returns the encrypted value.
  static Future<String> transformRequest(AtKey atKey, dynamic value) async {
    // Encode the value, if the value is of binary data.
    if (atKey.metadata!.isBinary) {
      value = Base2e15.encode(value);
    }

    // If key is public, Sign in the data.
    if (atKey is PublicKey || atKey.metadata!.isPublic) {
      atKey.metadata!.dataSignature = await SignInPublicData.signInData(
          value,
          await AtClientManager.getInstance()
              .atClient
              .getLocalSecondary()
              .getEncryptionPrivateKey());
      return value;
    }

    var encryptionService = AtKeyEncryptionManager.get(
        atKey, AtClientManager.getInstance().atClient.getCurrentAtSign());
    var encryptedValue =
        await encryptionService.encrypt(atKey, value) as String;
    atKey.metadata!.isEncrypted = true;
    return encryptedValue;
  }

  /// Decodes the binary data and decrypts the encrypted data and returns the
  /// [AtValue]
  /// NOTE: Use metadata from [AtValue]
  static Future<AtValue> transformResponse(AtValue atValue, AtKey atKey) async {
    if (atValue.metadata != null && atValue.metadata!.isBinary) {
      atValue.value = Base2e15.decode(atValue.value);
    }
    // Setting isEncrypted from atValue
    // because, user populated metadata will have false by default.
    atKey.metadata!.isEncrypted = atValue.metadata!.isEncrypted;

    var decryptionService = AtKeyDecryptionManager.get(
        atKey, AtClientManager.getInstance().atClient.getCurrentAtSign());
    decryptionService.decrypt(atKey, atValue.value);
    return atValue;
  }
}
