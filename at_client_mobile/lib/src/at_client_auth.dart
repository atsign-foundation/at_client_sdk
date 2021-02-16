import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_client_mobile/src/auth_constants.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

import 'keychain_manager.dart';

abstract class AtClientAuth {
  Future<bool> performInitialAuth(String atSign,
      {String cramSecret, String pkamPrivateKey});
}

class AtClientAuthenticator implements AtClientAuth {
  KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  AtLookupImpl atLookUp;
  bool _pkamAuthenticated = false;
  var logger = AtSignLogger('AtClientAuthenticator');

  Future<bool> init(var preference, {String atSign}) async {
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
    return await atLookUp.authenticate_cram(cramSecret);
  }

  Future<bool> pkamAuth(String privateKey) async {
    return await atLookUp.authenticate(privateKey);
  }

  @override
  Future<bool> performInitialAuth(String atSign,
      {String cramSecret, String pkamPrivateKey}) async {
    // get existing keys from keychain
    var publicKey =
        await _keyChainManager.getValue(atSign, KEYCHAIN_PKAM_PUBLIC_KEY);
    var privateKey = pkamPrivateKey ??=
        await _keyChainManager.getValue(atSign, KEYCHAIN_PKAM_PRIVATE_KEY);
    var encryptionPrivateKey = await _keyChainManager.getValue(
        atSign, KEYCHAIN_ENCRYPTION_PRIVATE_KEY);

    if (cramSecret != null) {
      logger.finer('private key is empty. Performing cram');
      var cram_result = await atLookUp.authenticate_cram(cramSecret);
      if (!cram_result) {
        return false;
      }
      var keypair;

      if (!_pkamAuthenticated) {
        // Generate keypair if not already generated
        if (privateKey == null || privateKey.isEmpty) {
          logger.finer('generating pkam key pair');
          keypair = _keyChainManager.generateKeyPair();
          privateKey = keypair.privateKey.toString();
          publicKey = keypair.publicKey.toString();
        }
        // send public key to remote Secondary server
        logger.finer('updating pkam public key to server');
        var updateCommand = 'update:${AT_PKAM_PUBLIC_KEY} $publicKey\n';
        // auth is false since already cram authenticated
        var pkamUpdateResult =
        await atLookUp.executeCommand(updateCommand, auth: false);
        logger.finer('pkam update result:${pkamUpdateResult}');
      } else {
        logger.finer('pkam auth already done');
        return true; //Auth already performed
      }
    }
    var pkam_auth_result = await atLookUp.authenticate(privateKey);

    if (pkam_auth_result) {
      logger.finer('pkam auth is successful');
      _pkamAuthenticated = true;
      if (privateKey != null) {
        // Save pkam public/private key pair in keychain
        await _keyChainManager.storeCredentialToKeychain(atSign,
            secret: cramSecret, privateKey: privateKey, publicKey: publicKey);
        // Generate key pair for encryption if not already present
        if (encryptionPrivateKey == null || encryptionPrivateKey == '') {
          logger
              .finer('generating encryption key pair and self encryption key');
          var encryptionKeyPair = _keyChainManager.generateKeyPair();
          await _keyChainManager.putValue(
              atSign,
              KEYCHAIN_ENCRYPTION_PRIVATE_KEY,
              encryptionKeyPair.privateKey.toString());
          var encryptionPubKey = encryptionKeyPair.publicKey.toString();
          await _keyChainManager.putValue(
              atSign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY, encryptionPubKey);
          var selfEncryptionKey = EncryptionUtil.generateAESKey();
          await _keyChainManager.putValue(
              atSign, KEYCHAIN_SELF_ENCRYPTION_KEY, selfEncryptionKey);
        }

        var deleteBuilder = DeleteVerbBuilder()..atKey = AT_CRAM_SECRET;
        var delete_response = await atLookUp.executeVerb(deleteBuilder);
        logger.finer('cram secret delete response : $delete_response');
      }
    }
    return true;
  }
}
