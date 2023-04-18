import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_auth_service.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_client_mobile/src/auth/at_authenticator.dart';
import 'package:at_client_mobile/src/auth/cram_authenticator.dart';
import 'package:at_client_mobile/src/auth/pkam_authenticator.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/cupertino.dart';

class AtAuthServiceImpl implements AtAuthService {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');

  @override
  AtChops? atChops;

  @visibleForTesting
  KeyChainManager keyChainManager = KeyChainManager.getInstance();

  PkamAuthenticator? pkamAuthenticator;

  CramAuthenticator? cramAuthenticator;

  @visibleForTesting
  AtClientManager atClientManager = AtClientManager.getInstance();

  @override
  Future<bool> isOnboarded({String? atSign}) async {
    // if atSign is not passed, read from keychain manager
    atSign ??= await keyChainManager.getAtSign();
    if (atSign == null) {
      return false;
    }
    AtsignKey? atSignKey = await keyChainManager.readAtsign(name: atSign);
    if (atSignKey == null) {
      return false;
    }
    // not checking pkam private key since it can be present in a secure element like a sim card
    if (_isNotEmpty(atSignKey.pkamPublicKey) &&
        _isNotEmpty(atSignKey.encryptionPrivateKey) &&
        _isNotEmpty(atSignKey.encryptionPublicKey) &&
        _isNotEmpty(atSignKey.selfEncryptionKey)) {
      return true;
    }
    return false;
  }

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    pkamAuthenticator ??= PkamAuthenticator(AtLookupImpl(
        atAuthRequest.atSign,
        atAuthRequest.preference.rootDomain,
        atAuthRequest.preference.rootPort));
    // 1. check if atsign is already onboarded
    if (await isOnboarded(atSign: atAuthRequest.atSign)) {
      //#TODO read keys and create at chops for this scenario
      return _pkamAuth(atAuthRequest.atSign);
    }
    // atsign is not onboarded and atkeys file data not passed
    if (atAuthRequest.atKeysData == null &&
        atAuthRequest.authMode == PkamAuthMode.keysFile) {
      throw AtClientException(error_codes['UnAuthenticatedException'],
          'atsign ${atAuthRequest.atSign} is not onboarded and atkeys file is not passed. Please call onboard first before trying authenticate');
    }

    // 2. decrypt the keys from keys data
    final atSignKey = _decodeAndDecryptKeys(
        atAuthRequest.atSign,
        atAuthRequest.atKeysData!.jsonData,
        atAuthRequest.atKeysData!.decryptionKey);

    // 3. persist keys to keychain
    await _persistKeysToKeyChain(atSignKey);

    // 4. create at chops instance if not set by the caller
    atChops ??= _createAtChops(
        AtEncryptionKeyPair.create(
            atSignKey.pkamPublicKey!, atSignKey.pkamPrivateKey!),
        AtPkamKeyPair.create(
            atSignKey.pkamPublicKey!, atSignKey.pkamPrivateKey!));

    // 5. init at client
    await _init(atAuthRequest.atSign, atAuthRequest.preference);

    // 6. persist keys to local secondary
    await atClientManager.atClient.persistKeys(
        atSignKey.pkamPrivateKey,
        atSignKey.pkamPublicKey!,
        atSignKey.encryptionPrivateKey!,
        atSignKey.encryptionPrivateKey!,
        atSignKey.selfEncryptionKey!);
    var atAuthResponse = AtAuthResponse(atAuthRequest.atSign);

    // 7. pkam auth using the created atClient instance
    try {
      atAuthResponse.isSuccessful = await atClientManager.atClient
          .getRemoteSecondary()!
          .atLookUp
          .pkamAuthenticate();
    } on UnAuthenticatedException catch (e) {
      atAuthResponse.isSuccessful = false;
      atAuthResponse.atClientException = AtClientException(
          error_codes['UnAuthenticatedException'], 'pkam auth failed for $e');
    }
    return atAuthResponse;
  }

  Future<AtAuthResponse> _pkamAuth(String atSign) async {
    final atAuthResponse = AtAuthResponse(atSign);
    try {
      final pkamAuthResult = await pkamAuthenticator!.authenticate(atSign);
      atAuthResponse.isSuccessful = pkamAuthResult.isSuccessful;
    } on AtClientException catch (e) {
      atAuthResponse.isSuccessful = false;
      atAuthResponse.atClientException = e;
    }
    return atAuthResponse;
  }

  @override
  Future<AtOnboardingResponse> onboard(
      AtOnboardingRequest atOnboardingRequest) async {
    var atSign = atOnboardingRequest.atSign;
    pkamAuthenticator ??= PkamAuthenticator(AtLookupImpl(
        atOnboardingRequest.atSign,
        atOnboardingRequest.preference.rootDomain,
        atOnboardingRequest.preference.rootPort));
    var onboardingResponse = AtOnboardingResponse(atSign);
    if (await isOnboarded(atSign: atSign)) {
      final pkamAuthResult = await pkamAuthenticator!.authenticate(atSign);
      onboardingResponse.isSuccessful = pkamAuthResult.isSuccessful;
      return onboardingResponse;
    }
    try {
      await _activateNewAtSign(atOnboardingRequest);
    } on AtClientException catch (e) {
      _logger
          .severe('exception in onboard -_activateNewAtSign : ${e.toString()}');
      onboardingResponse.isSuccessful = false;
      return onboardingResponse;
    }
    onboardingResponse.isSuccessful = true;
    return onboardingResponse;
  }

  Future<void> _activateNewAtSign(AtOnboardingRequest onboardingRequest) async {
    final atSign = onboardingRequest.atSign;
    try {
      // 1. cram auth
      cramAuthenticator ??= CramAuthenticator(
          onboardingRequest.preference!.cramSecret!,
          onboardingRequest.preference);
      final cramAuthResult =
          await cramAuthenticator!.authenticate(onboardingRequest.atSign);
      _logger.finer('cram auth result for $atSign : $cramAuthResult');

      // 2. generate pkam keypair and update pkam public key to server
      var pkamKeypair, pkamPublicKey, pkamPrivateKey;
      if (onboardingRequest.authMode == PkamAuthMode.sim) {
        if (atChops == null) {
          throw AtClientException(error_codes['AtClientException'],
              'atChops instance not set when auth mode is sim');
        }
        if (onboardingRequest.publicKeyId == null) {
          throw AtClientException(error_codes['AtClientException'],
              'publicKeyId from secure element has to be set when auth mode is sim');
        }
        pkamPublicKey = atChops!.readPublicKey(onboardingRequest.publicKeyId!);
      } else {
        pkamKeypair = keyChainManager.generateKeyPair();
        pkamPublicKey = pkamKeypair.publicKey.toString();
        pkamPrivateKey = pkamKeypair.privateKey.toString();
        atChops ??= _createAtChops(
            null,
            AtPkamKeyPair.create(pkamPublicKey,
                pkamPrivateKey)); // set encryption key pair after generation
      }
      //#TODO test whether this update verb builder will generate the desired command
      var updatePkamPublicKeyResult =
          await cramAuthenticator!.atLookup!.executeVerb(UpdateVerbBuilder()
            ..atKey = AT_PKAM_PUBLIC_KEY
            ..value = pkamPublicKey);
      _logger.finer('updatePkamPublicKeyResult:  $updatePkamPublicKeyResult');

      // 3. pkam auth
      final pkamAuthResult = await pkamAuthenticator!.authenticate(atSign);
      _logger.finer('pkam auth result for $atSign: $pkamAuthResult');
      if (pkamAuthResult.isSuccessful == false) {
        throw AtClientException(error_codes['UnAuthenticatedException'],
            '_activateNewAtSign - initial pkam failed');
      }
      // 4. Generate encryption and self encryption key pair if pkam auth is successful and keysfile is not passed
      final encryptionKeyPair = keyChainManager.generateKeyPair();
      final selfEncryptionKey = keyChainManager.generateSelfEncryptionKey();
      atChops!.atChopsKeys.atEncryptionKeyPair = AtEncryptionKeyPair.create(
          encryptionKeyPair.publicKey.toString(),
          encryptionKeyPair.privateKey.toString());
      atChops!.atChopsKeys.symmetricKey = AESKey(selfEncryptionKey);
      await _init(atSign, onboardingRequest.preference);
      var atSignKey = await keyChainManager.readAtsign(name: atSign) ??
          AtsignKey(atSign: atSign);
      atSignKey = atSignKey.copyWith(
        pkamPrivateKey: pkamPrivateKey,
        pkamPublicKey: pkamPublicKey,
        encryptionPrivateKey: encryptionKeyPair.privateKey.toString(),
        encryptionPublicKey: encryptionKeyPair.publicKey.toString(),
        selfEncryptionKey: selfEncryptionKey,
      );
      await _persistKeysToKeyChain(atSignKey);
      // 5. persist keys to local secondary
      await atClientManager.atClient.persistKeys(
          pkamPrivateKey,
          pkamPublicKey,
          encryptionKeyPair.privateKey.toString(),
          encryptionKeyPair.publicKey.toString(),
          selfEncryptionKey);

      //6. delete cram secret from server
      var deleteBuilder = DeleteVerbBuilder()..atKey = AT_CRAM_SECRET;
      var deleteResponse =
          await cramAuthenticator!.atLookup!.executeVerb(deleteBuilder);
      _logger.finer('delete cram secret response : $deleteResponse');
    } on AtClientException {
      rethrow;
    }
  }

  Future<void> _persistKeysToKeyChain(AtsignKey atsignKey) async {
    //#TODO should we also call _keyChainManager.storePkamKeysToKeychain ?
    // difference between _keyChainManager.storePkamKeysToKeychain and _keyChainManager.storeCredentialToKeychain
    await keyChainManager.storeAtSign(atSign: atsignKey);
  }

  bool _isNotEmpty(String? key) {
    return key != null && key.isNotEmpty;
  }

  Future<bool> _init(String atSign, AtClientPreference preference) async {
    preference.useAtChops = true;
    await atClientManager.setCurrentAtSign(
        atSign, preference.namespace, preference,
        atChops: atChops);
    if (preference.outboundConnectionTimeout > 0) {
      atClientManager.atClient
          .getRemoteSecondary()!
          .atLookUp
          .outboundConnectionTimeout = preference.outboundConnectionTimeout;
    }
    return true;
  }

  AtChops _createAtChops(
      AtEncryptionKeyPair? atEncryptionKeyPair, AtPkamKeyPair atPkamKeyPair) {
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    final atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }

  ///Decodes the [jsonData] with [decryptKey] and returns the original keys in object [AtsignKey]
  AtsignKey _decodeAndDecryptKeys(
      String atSign, String jsonData, String decryptKey) {
    var extractedJsonData = jsonDecode(jsonData);

    var pkamPublicKey = EncryptionUtil.decryptValue(
        extractedJsonData[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE],
        decryptKey);

    var pkamPrivateKey = EncryptionUtil.decryptValue(
        extractedJsonData[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE],
        decryptKey);

    var encryptionPublicKey = EncryptionUtil.decryptValue(
        extractedJsonData[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE],
        decryptKey);

    var encryptionPrivateKey = EncryptionUtil.decryptValue(
        extractedJsonData[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE],
        decryptKey);

    return AtsignKey(
        atSign: atSign,
        pkamPrivateKey: pkamPrivateKey,
        pkamPublicKey: pkamPublicKey,
        encryptionPrivateKey: encryptionPrivateKey,
        encryptionPublicKey: encryptionPublicKey,
        selfEncryptionKey: decryptKey);
  }
}
