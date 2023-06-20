import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_chops/at_chops.dart';

/// Class responsible for decrypting the value of self key's
/// Example:
/// CurrentAtSign: @bob and
/// llookup:phone.wavi@bob
/// llookup:@bob:phone@bob
class SelfKeyDecryption implements AtKeyDecryption {
  final AtClient _atClient;
  SelfKeyDecryption(this._atClient);
  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic encryptedValue) async {
    RegExp encryptedSharedKeyMatcher =
        RegExp(r'^shared_key\..+@.+|@.+:shared_key@.+');

    if (encryptedValue == null ||
        encryptedValue.isEmpty ||
        encryptedValue == 'null') {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }
    if (atKey.key!.startsWith(encryptedSharedKeyMatcher)) {
      var privateEncryptionKey =
          await _atClient.getLocalSecondary()!.getEncryptionSelfKey();
      if ((privateEncryptionKey == null || privateEncryptionKey.isEmpty) ||
          privateEncryptionKey == 'data:null') {
        throw SelfKeyNotFoundException('Empty or null SelfEncryptionKey found',
            intent: Intent.fetchEncryptionPrivateKey,
            exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
      }
      return EncryptionUtil.decryptValue(encryptedValue,
          DefaultResponseParser().parse(privateEncryptionKey).response,
          ivBase64: atKey.metadata?.ivNonce);
    }
    var selfEncryptionKey =
        await _atClient.getLocalSecondary()!.getEncryptionSelfKey();
    if ((selfEncryptionKey == null || selfEncryptionKey.isEmpty) ||
        selfEncryptionKey == 'data:null') {
      throw SelfKeyNotFoundException('Empty or null SelfEncryptionKey found',
          intent: Intent.fetchSelfEncryptionKey,
          exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
    }
    return EncryptionUtil.decryptValue(encryptedValue,
        DefaultResponseParser().parse(selfEncryptionKey).response,
        ivBase64: atKey.metadata?.ivNonce);
  }
}
