import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/response/default_response_parser.dart';

/// Class responsible for decrypting the value of self key's
/// Example:
/// CurrentAtSign: @bob and
/// llookup:phone.wavi@bob
/// llookup:@bob:phone@bob
class SelfKeyDecryption implements AtKeyDecryption {
  SelfKeyDecryption(this._atClient);
  final AtClient _atClient;
  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic encryptedValue) async {
    if (encryptedValue == null ||
        encryptedValue.isEmpty ||
        encryptedValue == 'null') {
      throw AtDecryptionException('Decryption failed. Encrypted value is null',
          intent: Intent.decryptData,
          exceptionScenario: ExceptionScenario.decryptionFailed);
    }
    if (atKey.key == "shared_key") {
      var privateEncryptionKey =
          await _atClient.getLocalSecondary()!.getEncryptionPrivateKey();
      var publicEncryptionKey = await _atClient
          .getLocalSecondary()!
          .getEncryptionPublicKey(atKey.sharedBy!);
      var publicKey = await _atClient.getLocalSecondary()!.getPublicKey();
      var privateKey = await _atClient.getLocalSecondary()!.getPrivateKey();

      if ((privateEncryptionKey == null || privateEncryptionKey.isEmpty) ||
          privateEncryptionKey == 'data:null') {
        throw SelfKeyNotFoundException('Empty or null SelfEncryptionKey found',
            intent: Intent.fetchEncryptionPrivateKey,
            exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
      }

      //I know there's definetly a better way to do this but I'm way too tired.
      // I'll try again tmw. (Maybe reading them from .atKeys file?)

      AtChops _chops = AtChopsImpl(AtChopsKeys.create(
          AtEncryptionKeyPair.create(
              publicEncryptionKey!, privateEncryptionKey),
          AtPkamKeyPair.create(publicKey!, privateKey!)));
      return _chops.decryptString(encryptedValue, EncryptionKeyType.rsa2048);
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
