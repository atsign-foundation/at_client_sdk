import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';

abstract class AtClientAuth {
  Future<bool> performInitialAuth(
      String atSign, AtClientPreference atClientPreference);
}

class AtClientAuthenticator implements AtClientAuth {
  KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  late AtLookupImpl atLookUp;
  bool _isPKAMAuthenticated = false;
  var logger = AtSignLogger('AtClientAuthenticator');

  Future<bool?> init(var preference, {String? atSign}) async {
    _keyChainManager = KeyChainManager.getInstance();
    if (atSign == null || atSign.isEmpty) {
      atSign = await _keyChainManager.getAtSign();
      if (atSign == null || atSign.isEmpty) {
        return null;
      }
    }
    return true;
  }

  Future<bool> cramAuth(String cramSecret) async {
    return await atLookUp.cramAuthenticate(cramSecret);
  }

  Future<bool> pkamAuth(String privateKey) async {
    return await atLookUp.authenticate(privateKey);
  }

  @override
  Future<bool> performInitialAuth(
      String atSign, AtClientPreference atClientPreference) async {
    var atLookupInitialAuth = AtLookupImpl(
        atSign, atClientPreference.rootDomain, atClientPreference.rootPort);
    // get existing keys from keychain
    final atsign = await _keyChainManager.readAtsign(name: atSign);
    var publicKey = atsign?.pkamPublicKey;
    var privateKey = atClientPreference.privateKey ??= atsign?.pkamPrivateKey;
    var encryptionPrivateKey = atsign?.encryptionPublicKey;

    // If cram secret is null, perform cram authentication
    if (atClientPreference.cramSecret != null) {
      logger.finer('private key is empty. Performing cram');
      var isCramSuccessful = await atLookupInitialAuth
          .cramAuthenticate(atClientPreference.cramSecret!);
      // If cram auth is not successful, return false.
      if (!isCramSuccessful) {
        return false;
      }

      RSAKeypair keypair;
      // If PKAM Authenticated is false, perform PKAM auth
      if (!_isPKAMAuthenticated) {
        // Generate keypair if not already generated
        if (privateKey == null || privateKey.isEmpty) {
          logger.finer('generating pkam key pair');
          keypair = _keyChainManager.generateKeyPair();
          privateKey = keypair.privateKey.toString();
          publicKey = keypair.publicKey.toString();
        }
        // send public key to remote Secondary server
        logger.finer('updating pkam public key to server');
        var updateCommand =
            'update:${AtConstants.atPkamPublicKey} $publicKey\n';
        // auth is false since already cram authenticated
        var pkamUpdateResult = await atLookupInitialAuth
            .executeCommand(updateCommand, auth: false);
        logger.finer('pkam update result:$pkamUpdateResult');
      } else {
        logger.finer('pkam auth already done');
        return true; //Auth already performed
      }
    }
    var pkamAuthResult = await atLookupInitialAuth.authenticate(privateKey);

    if (pkamAuthResult) {
      logger.finer('pkam auth is successful');
      _isPKAMAuthenticated = true;
      if (privateKey != null) {
        // Save pkam public/private key pair in keychain
        await _keyChainManager.storeCredentialToKeychain(atSign,
            secret: atClientPreference.cramSecret,
            privateKey: privateKey,
            publicKey: publicKey);
        // Generate key pair for encryption if not already present
        if (encryptionPrivateKey == null || encryptionPrivateKey == '') {
          logger
              .finer('generating encryption key pair and self encryption key');
          var encryptionKeyPair = _keyChainManager.generateKeyPair();
          var atSignItem = await _keyChainManager.readAtsign(name: atSign) ??
              AtsignKey(atSign: atSign);
          atSignItem = atSignItem.copyWith(
            encryptionPrivateKey: encryptionKeyPair.privateKey.toString(),
            encryptionPublicKey: encryptionKeyPair.publicKey.toString(),
            selfEncryptionKey: EncryptionUtil.generateAESKey(),
          );
          await _keyChainManager.storeAtSign(atSign: atSignItem);
        }
        var deleteBuilder = DeleteVerbBuilder()
          ..atKey = (AtKey()..key = AtConstants.atCramSecret);
        var deleteResponse =
            await atLookupInitialAuth.executeVerb(deleteBuilder);
        logger.finer('cram secret delete response : $deleteResponse');
      }
    }
    // Close the connection on atLookupInitalAuth.
    await atLookupInitialAuth.close();
    return true;
  }
}
