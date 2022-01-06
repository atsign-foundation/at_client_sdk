import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_commons/at_commons.dart';

class AtValues {
  /// Decodes the binary data and decrypts the encrypted data and returns the
  /// [AtValue]
  /// NOTE: Use metadata from [AtValue]
  static Future<AtValue> transformResponse(AtValue atValue, AtKey atKey) async {
    if (atValue.metadata != null && atValue.metadata!.isBinary) {
      atValue.value = Base2e15.decode(atValue.value);
    }

    if ((atValue.metadata != null && atValue.metadata!.isEncrypted) &&
        AtClientManager.getInstance().atClient.getCurrentAtSign() !=
            atKey.sharedBy) {
      atValue.value = await AtClientManager.getInstance()
          .atClient
          .encryptionService
          .decrypt(atValue.value, atKey.sharedBy!);
      return atValue;
    }

    // for llookup
    // @alice:phone@bob
    // @alice:phone@alice
    // phone@alice
    if ((atValue.metadata != null && atValue.metadata!.isEncrypted) &&
        AtClientManager.getInstance().atClient.getCurrentAtSign() ==
            atKey.sharedBy) {
      atValue.value = await AtClientManager.getInstance()
          .atClient
          .encryptionService
          .decryptLocal(
              atValue.value,
              AtClientManager.getInstance().atClient.getCurrentAtSign(),
              atKey.sharedWith!);
    }

    // for private keys
    //_phone@alice
    if ((atValue.metadata != null && atValue.metadata!.isEncrypted) &&
        AtClientManager.getInstance().atClient.getCurrentAtSign() ==
            atKey.sharedWith) {
      atValue.value = await AtClientManager.getInstance()
          .atClient
          .encryptionService
          .decryptForSelf(atValue.value, atKey.metadata!.isEncrypted);
    }

    return atValue;
  }

  static Future<String> transformRequest(AtKey atKey, dynamic value) async {
    // Encode the value, if the value is of binary data.
    if (atKey.metadata!.isBinary) {
      value = Base2e15.encode(value);
    }
    // If sharedWith atSign is not equal to currentAtSign, encrypt the data.
    if (atKey.sharedWith != null &&
        atKey.sharedWith !=
            AtClientManager.getInstance().atClient.getCurrentAtSign()) {
      try {
        value = await AtClientManager.getInstance()
            .atClient
            .encryptionService
            .encrypt(atKey.key, value, atKey.sharedWith!);
        atKey.metadata!.isEncrypted = true;
        return value;
      } on KeyNotFoundException catch (e) {
        var errorCode = AtClientExceptionUtil.getErrorCode(e);
        return Future.error(AtClientException(errorCode, e.message));
      }
    }
    // If the key is private key, perform the self encryption.
    // @sitram:phone@sitaram
    // _phone@sitaram
    if (!atKey.metadata!.isPublic && !atKey.key.startsWith('_')) {
      value = await AtClientManager.getInstance()
          .atClient
          .encryptionService
          .encryptForSelf(atKey.key, value);
      atKey.metadata!.isEncrypted = true;
      return value;
    }
    // If the key is public, sign the public data with private encryption key
    // verify the
    if (atKey.metadata!.isPublic) {
      try {
        var encryptionPrivateKey = await AtClientManager.getInstance()
            .atClient
            .getLocalSecondary()
            .getEncryptionPrivateKey();
        // If encryptionPrivateKey is not found, throw error.
        if (encryptionPrivateKey.isEmpty) {
          return Future.error(AtClientException(
              atClientErrorCodes['AtClientException'],
              'Failed signing the public data. Encryption private key not found'));
        }
        atKey.metadata!.dataSignature = AtClientManager.getInstance()
            .atClient
            .encryptionService
            .signPublicData(encryptionPrivateKey, value);
      } on Exception catch (e) {
        return Future.error(AtClientException(
            atClientErrorCodes['AtClientException'],
            'Exception trying to sign public data:${e.toString()}'));
      }
    }
    return value;
  }
}
