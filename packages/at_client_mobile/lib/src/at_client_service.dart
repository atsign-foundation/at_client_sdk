import 'dart:convert';
import 'dart:core';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_chops/at_chops.dart';
import 'package:flutter/cupertino.dart';

class AtClientService {
  final AtSignLogger _logger = AtSignLogger('AtClientService');
  AtClient? _atClient;
  AtClientManager atClientManager = AtClientManager.getInstance();

  @visibleForTesting
  AtClientAuthenticator? atClientAuthenticator;

  AtLookupImpl? _atLookUp;

  @visibleForTesting
  set atLookupImpl(AtLookupImpl atLookupImpl) {
    _atLookUp = atLookupImpl;
  }

  AtLookupImpl get atLookupImpl => _atLookUp!;

  @visibleForTesting
  KeyChainManager keyChainManager = KeyChainManager.getInstance();

  // Will create at client instance for a given atSign and perform cram+pkam auth to the server.
  // if pkam is successful, encryption keys will be set for the user./// Will create at client instance for a given atSign.
  Future<bool> _init(
      String atSign, AtClientPreference preference, AtChops atChops) async {
    atClientAuthenticator ??= AtClientAuthenticator();
    await atClientManager.setCurrentAtSign(
        atSign, preference.namespace, preference,
        atChops: atChops);
    _atClient = atClientManager.atClient;
    _atLookUp = _atClient!.getRemoteSecondary()!.atLookUp;
    if (preference.outboundConnectionTimeout > 0) {
      _atClient!.getRemoteSecondary()!.atLookUp.outboundConnectionTimeout =
          preference.outboundConnectionTimeout;
    }
    atClientAuthenticator!.atLookUp = _atClient!.getRemoteSecondary()!.atLookUp;
    return true;
  }

  Future<bool> cramAuth(String cramSecret) async {
    return await atClientAuthenticator!.cramAuth(cramSecret);
  }

  Future<bool> pkamAuth(String privateKey) async {
    return await atClientAuthenticator!.pkamAuth(privateKey);
  }

  /// Returns the PKAM key-pair, encryption key-pair and self encryption key from the KeyChain Manager
  @visibleForTesting
  Future<Map<String, String>> getKeysFromKeyChainManager(String atSign) async {
    Map<String, String> atKeysMap = {};
    // Validate PKAM Private Key
    (await keyChainManager.getPkamPrivateKey(atSign)).isNull
        ? throw (OnboardingStatus.PKAM_PRIVATE_KEY_NOT_FOUND)
        : atKeysMap[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE] =
            (await keyChainManager.getPkamPrivateKey(atSign))!;
    // Validate PKAM Public Key
    (await keyChainManager.getPkamPublicKey(atSign)).isNull
        ? throw (OnboardingStatus.PKAM_PUBLIC_KEY_NOT_FOUND)
        : atKeysMap[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE] =
            (await keyChainManager.getPkamPublicKey(atSign))!;
    // Validate Encryption Private Key
    (await keyChainManager.getEncryptionPrivateKey(atSign)).isNull
        ? throw (OnboardingStatus.ENCRYPTION_PRIVATE_KEY_NOT_FOUND)
        : atKeysMap[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE] =
            (await keyChainManager.getEncryptionPrivateKey(atSign))!;
    // Validate Encryption Public Key
    (await keyChainManager.getEncryptionPublicKey(atSign)).isNull
        ? throw (OnboardingStatus.ENCRYPTION_PUBLIC_KEY_NOT_FOUND)
        : atKeysMap[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE] =
            (await keyChainManager.getEncryptionPublicKey(atSign))!;
    // Validate Self Encryption Key
    (await keyChainManager.getSelfEncryptionAESKey(atSign)).isNull
        ? throw (OnboardingStatus.SELF_ENCRYPTION_KEY_NOT_FOUND)
        : atKeysMap[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE] =
            (await keyChainManager.getSelfEncryptionAESKey(atSign))!;

    return atKeysMap;
  }

  ///Returns `true` on persisting keys into keystore.
  Future<bool> persistKeys(String atSign) async {
    // Get keys from KeyChain manager
    String? pkamPrivateKey = await keyChainManager.getPkamPrivateKey(atSign);
    String? pkamPublicKey = await keyChainManager.getPkamPublicKey(atSign);
    String? encryptPrivateKey =
        await keyChainManager.getEncryptionPrivateKey(atSign);
    String? encryptPublicKey =
        await keyChainManager.getEncryptionPublicKey(atSign);
    String? selfEncryptionKey =
        await keyChainManager.getSelfEncryptionAESKey(atSign);

    // If the keys are missed, the authentication and encryption/decryption of data
    // does not work. Hence first throwing exception without going further.
    if (pkamPrivateKey == null || pkamPrivateKey.isEmpty) {
      throw (OnboardingStatus.PKAM_PRIVATE_KEY_NOT_FOUND);
    }
    if (pkamPublicKey == null || pkamPublicKey.isEmpty) {
      throw (OnboardingStatus.PKAM_PUBLIC_KEY_NOT_FOUND);
    }
    if (encryptPrivateKey == null || encryptPrivateKey.isEmpty) {
      throw (OnboardingStatus.ENCRYPTION_PRIVATE_KEY_NOT_FOUND);
    }
    if (encryptPublicKey == null || encryptPublicKey.isEmpty) {
      throw (OnboardingStatus.ENCRYPTION_PUBLIC_KEY_NOT_FOUND);
    }
    if (selfEncryptionKey == null || selfEncryptionKey.isEmpty) {
      throw (OnboardingStatus.SELF_ENCRYPTION_KEY_NOT_FOUND);
    }

    //Store keys into local secondary.
    await _atClient!
        .getLocalSecondary()!
        .putValue(AtConstants.atPkamPublicKey, pkamPublicKey);

    await _atClient!
        .getLocalSecondary()!
        .putValue(AtConstants.atPkamPrivateKey, pkamPrivateKey);

    await _atClient!
        .getLocalSecondary()!
        .putValue(AtConstants.atEncryptionPrivateKey, encryptPrivateKey);

    var updateBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey'
      ..isPublic = true
      ..sharedBy = atSign
      ..value = encryptPublicKey
      ..metadata.ttr = -1;

    await _atClient!
        .getLocalSecondary()!
        .executeVerb(updateBuilder, sync: true);

    await _atClient!
        .getLocalSecondary()!
        .putValue(AtConstants.atEncryptionSelfKey, selfEncryptionKey);

    // Verify if keys are added to local storage.
    var result = await _getKeysFromLocalSecondary(atSign);
    return result;
  }

  ///Throws [Error] of type [OnboardingStatus]
  ///if the details for [atsign] is not found in localsecondary.
  ///Returns `true` on successful fetching of all the details.
  Future<bool> _getKeysFromLocalSecondary(String atsign) async {
    String? pkamPublicKey =
        await _atClient!.getLocalSecondary()!.getPublicKey();
    if (pkamPublicKey == null || pkamPublicKey.isEmpty) {
      throw (OnboardingStatus.PKAM_PUBLIC_KEY_NOT_FOUND);
    }
    String? pkamPrivateKey =
        await _atClient!.getLocalSecondary()!.getPrivateKey();
    if (pkamPrivateKey == null || pkamPrivateKey.isEmpty) {
      throw (OnboardingStatus.PKAM_PRIVATE_KEY_NOT_FOUND);
    }
    String? encryptPrivateKey =
        await _atClient!.getLocalSecondary()!.getEncryptionPrivateKey();
    if (encryptPrivateKey == null || encryptPrivateKey.isEmpty) {
      throw (OnboardingStatus.ENCRYPTION_PRIVATE_KEY_NOT_FOUND);
    }
    String? encryptPublicKey =
        await _atClient!.getLocalSecondary()!.getEncryptionPublicKey(atsign);
    if (encryptPublicKey == null || encryptPublicKey.isEmpty) {
      throw (OnboardingStatus.ENCRYPTION_PUBLIC_KEY_NOT_FOUND);
    }
    String? encryptSelfKey =
        await _atClient!.getLocalSecondary()!.getEncryptionSelfKey();
    if (encryptSelfKey == null || encryptSelfKey.isEmpty) {
      throw (OnboardingStatus.SELF_ENCRYPTION_KEY_NOT_FOUND);
    }
    return true;
  }

  ///Returns `true` on successfully authenticating [atsign] with [cramSecret]/[privateKey].
  /// if pkam is successful, encryption keys will be set for the user.
  @Deprecated('Use AtAuthService.authenticate method')
  Future<bool> authenticate(
      String atsign, AtClientPreference atClientPreference,
      {OnboardingStatus? status, String? jsonData, String? decryptKey}) async {
    /**ToDo Use OnboardingStatus enum instead of using
        atClientPreferences.cramSecret == null to know if atSign is new or existing
        If status == OnboardingStatus.ACTIVATE, then atSign is new, so perform initial auth and
        generate RSA key-pair
        If status == OnboardingStatus.RESTORE then use use atKeys file to login into existing atSign
     */
    /**
     * The authentication is performed either by CRAM authentication or PKAM authentication
     * 1. If AtClientPreference.cramSecret is populated, then atSign is considered as new atSign.
     * So, perform CRAM auth and if successful, generate PKAM key-pair and encryption key-pair
     * and store them into key-chain manager and return true, else false.
     * 2. If AtClientPreference.privateKey is populated, then atSign is considered as existing atSign.
     * So, first verify if .atKeys file provided have valid key-pair. Perform PKAM auth to validate the
     * key-pair. If successful, store the keys into key-chain manager and return true, else false.
     **/
    // _formatAtSign method checks if atSign is prefixed with '@',
    // If '@' is not prefixed, prefixes '@' and returns @sign.
    // If atSign is null or empty, returns empty string.
    atsign = _formatAtSign(atsign);
    // atSign is mandatory to authenticate. So, if atSign is empty return
    // false to indicate authentication is not successful
    if (atsign.isEmpty) {
      _logger.severe('Authentication failed. Null or empty atSign found.');
      return false;
    }
    AtChops? atChops;
    if (atClientPreference.cramSecret.isNull) {
      // If JSON data (encrypted keys from .atKeys file) or decrypt key is null or empty,
      // cannot process authentication. Hence return false.
      //
      // "isNull" is an extension on String class that checks if String is null or empty.
      if ((jsonData.isNull) || (decryptKey.isNull)) {
        _logger.severe(
            'Authentication failed. Encrypted keys from atKeys file not found for the atSign $atsign.');
        return false;
      }
      var decryptedAtKeysMap = _decodeAndDecryptKeys(jsonData!, decryptKey!);
      atChops = createAtChops(decryptedAtKeysMap);
      // Inside "_validateAtKeys", performs PKAM auth using atChops.
      // If PKAM auth fails, UnAuthenticatedException is returned which is handled in the caller method.
      var isValidAtKeysFile = await _validateAtKeys(atChops, atsign,
          atClientPreference.rootDomain, atClientPreference.rootPort);
      if (!isValidAtKeysFile) {
        _logger.severe(
            'Authentication failed. Invalid atKeys file found for the atSign $atsign.');
        return false;
      }
      //If atKeys are valid, store keys to keychain manager
      await _storeToKeyChainManager(atsign, decryptedAtKeysMap);
    }
    // Perform the initial auth using CRAM Secret and then
    // Generate the PKAM and encryption key-pair and create the atChops instance.
    else {
      atClientAuthenticator ??= AtClientAuthenticator();
      var isAuthenticated = await atClientAuthenticator!
          .performInitialAuth(atsign, atClientPreference);
      // If authentication is failed, return false.
      if (!isAuthenticated) {
        return isAuthenticated;
      }
      // The "getKeysFromKeyChainManager" fetches PKAM key-pair and encryption key-pair
      // from the keychain. throws exception if any of the key is null or empty.
      // The createAtChops method takes PKAM and encryption key-pair map and returns
      // atChops instance with fields initialized.
      atChops = createAtChops(await getKeysFromKeyChainManager(atsign));
    }
    await _init(atsign, atClientPreference, atChops);
    await _sync();
    // persist keys to the local-keystore
    await persistKeys(atsign);
    return true;
  }

  ///Decodes the [jsonData] with [decryptKey] and returns the original keys in a map
  Map<String, String> _decodeAndDecryptKeys(
      String jsonData, String decryptKey) {
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

    var atKeysMap = {
      BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE: pkamPrivateKey,
      BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE: pkamPublicKey,
      BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE: encryptionPrivateKey,
      BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE: encryptionPublicKey,
      BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE: decryptKey
    };
    return atKeysMap;
  }

  /// Stores the atKeys to Key-Chain Manager.
  Future<void> _storeToKeyChainManager(
      String atsign, Map<String, String> atKeysMap) async {
    await keyChainManager.storePkamKeysToKeychain(atsign,
        privateKey:
            atKeysMap[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE],
        publicKey: atKeysMap[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE]);

    var atSignItem = await keyChainManager.readAtsign(name: atsign) ??
        AtsignKey(atSign: atsign);
    atSignItem = atSignItem.copyWith(
      encryptionPrivateKey:
          atKeysMap[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE],
      encryptionPublicKey:
          atKeysMap[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE],
      selfEncryptionKey:
          atKeysMap[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE],
    );

    await keyChainManager.storeAtSign(atSign: atSignItem);

    // Add atSign to the keychain.
    await keyChainManager.storeCredentialToKeychain(atsign,
        privateKey:
            atKeysMap[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE],
        publicKey: atKeysMap[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE]);
  }

  /// Validates if the provided atKeys file is valid.
  /// Performs PKAM auth on the cloud secondary.
  /// If atKeys are valid returns true; else, returns false.
  Future<bool> _validateAtKeys(AtChops atChops, String atSign,
      String rootServerDomain, int rootServerPort) async {
    _atLookUp ??= AtLookupImpl(atSign, rootServerDomain, rootServerPort);
    _atLookUp!.atChops = atChops;
    var isAuthSuccessful = await _atLookUp!.pkamAuthenticate();
    _atLookUp!.close();
    return isAuthSuccessful;
  }

  Future<bool?> isUsingSharedStorage() async {
    return keyChainManager.isUsingSharedStorage();
  }

  Future<void> config({required bool useSharedStorage}) async {
    await keyChainManager.initialSetup(useSharedStorage: useSharedStorage);
  }

  ///Returns `true` on successfully completing onboarding.
  /// Throws [OnboardingStatus.atSignNotFound] exception if atsign not found.
  /// Throws [OnboardingStatus.privateKeyNotFound] exception if privatekey not found.
  @Deprecated('Use AtAuthService.onboard method')
  Future<bool> onboard(
      {required AtClientPreference atClientPreference, String? atsign}) async {
    AtChops? atChops;
    // If optional argument "atSign" is null, fetches the atSign from the keyChainManager
    if (atsign.isNull) {
      atsign = await keyChainManager.getAtSign();
    }
    atsign = _formatAtSign(atsign);
    if (atsign.isNull) {
      _logger.severe('$atsign atSign is not found');
      throw OnboardingStatus.ATSIGN_NOT_FOUND;
    }
    atChops = createAtChops(await getKeysFromKeyChainManager(atsign));
    await _init(atsign, atClientPreference, atChops);
    await persistKeys(atsign);
    var keyRestorePolicyStatus = await getKeyRestorePolicy(atsign);
    if (keyRestorePolicyStatus == OnboardingStatus.ACTIVATE ||
        keyRestorePolicyStatus == OnboardingStatus.RESTORE) {
      throw (keyRestorePolicyStatus);
    }
    await _sync();
    return true;
  }

  ///Returns [OnboardingStatus] of the atsign by checking it with remote server.
  Future<OnboardingStatus> getKeyRestorePolicy(String atSign) async {
    var serverEncryptionPublicKey = await _getServerEncryptionPublicKey(atSign);
    var localEncryptionPublicKey =
        await keyChainManager.getEncryptionPublicKey(atSign);
    if (_isNullOrEmpty(localEncryptionPublicKey) &&
            _isNullOrEmpty(serverEncryptionPublicKey) ||
        (_isNullOrEmpty(serverEncryptionPublicKey) &&
            !(_isNullOrEmpty(localEncryptionPublicKey)))) {
      return OnboardingStatus.ACTIVATE;
    } else if (!_isNullOrEmpty(serverEncryptionPublicKey) &&
        _isNullOrEmpty(localEncryptionPublicKey)) {
      return OnboardingStatus.RESTORE;
    } else if (_isNullOrEmpty(serverEncryptionPublicKey) &&
        !_isNullOrEmpty(localEncryptionPublicKey)) {
      return OnboardingStatus.SYNC_TO_SERVER;
    } else {
      //both keys not null
      if (serverEncryptionPublicKey == localEncryptionPublicKey) {
        return OnboardingStatus.REUSE;
      } else {
        return OnboardingStatus.RESTORE;
      }
    }
  }

  /// Initiates Sync Process.
  Future<void> _sync() async {
    atClientManager.atClient.syncService.sync();
  }

  ///returns public key for [atsign] if found else returns null.
  Future<String?> _getServerEncryptionPublicKey(String atsign) async {
    var command = 'lookup:publickey$atsign\n';
    var result = await _atLookUp?.executeCommand(command);
    if (_isNullOrEmpty(result) || _isError(result)) {
      //checking for an authenticated connection
      command = 'llookup:public:publickey$atsign\n';
      result = await _atLookUp?.executeCommand(command);
      if (_isNullOrEmpty(result) || _isError(result)) {
        return null;
      }
    }
    return result!.replaceFirst('data:', '');
  }

  bool _isNullOrEmpty(String? key) {
    if (key == null) {
      return true;
    }
    key = key.replaceFirst('data:', '');
    if (key == 'null' || key.isEmpty) {
      return true;
    }
    return false;
  }

  bool _isError(String? key) {
    return key != null ? key.contains('error') : false;
  }

  ///Returns null if [atsign] is null else the formatted [atsign].
  ///[atsign] must be non-null.
  String _formatAtSign(String? atsign) {
    if (atsign.isNull) {
      return '';
    }
    atsign = atsign!.trim().toLowerCase().replaceAll(' ', '');
    atsign = !atsign.startsWith('@') ? '@$atsign' : atsign;
    return atsign;
  }

  /// Creates and returns an an AtChops instance
  @visibleForTesting
  AtChops createAtChops(Map<String, String> decryptedAtKeys) {
    final atEncryptionKeyPair = AtEncryptionKeyPair.create(
        decryptedAtKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE]!,
        decryptedAtKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE]!);
    final atPkamKeyPair = AtPkamKeyPair.create(
        decryptedAtKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE]!,
        decryptedAtKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE]!);
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    final atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }
}

class BackupKeyConstants {
  // ignore_for_file: constant_identifier_names
  static const String PKAM_PUBLIC_KEY_FROM_KEY_FILE = 'aesPkamPublicKey';
  static const String PKAM_PRIVATE_KEY_FROM_KEY_FILE = 'aesPkamPrivateKey';
  static const String ENCRYPTION_PUBLIC_KEY_FROM_FILE = 'aesEncryptPublicKey';
  static const String ENCRYPTION_PRIVATE_KEY_FROM_FILE = 'aesEncryptPrivateKey';
  static const String SELF_ENCRYPTION_KEY_FROM_FILE = 'selfEncryptionKey';
  static const String APKAM_SYMMETRIC_KEY_FROM_FILE = 'apkamSymmetricKey';
  static const String APKAM_ENROLLMENT_ID_FROM_FILE = 'enrollmentId';
}

class KeychainUtil {
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

  static Future<String?> getPkamPrivateKey(String atSign) async {
    var pkamPrivateKey = await _keyChainManager.getPkamPrivateKey(atSign);
    return pkamPrivateKey;
  }

  static Future<String?> getPkamPublicKey(String atSign) async {
    return await _keyChainManager.getPkamPublicKey(atSign);
  }

  static Future<String?> getPrivateKey(String atSign) async {
    return await getPkamPrivateKey(atSign);
  }

  static Future<String?> getPublicKey(String atSign) async {
    return await getPkamPublicKey(atSign);
  }

  static Future<String?> getEncryptionPrivateKey(String atSign) async {
    return await _keyChainManager.getEncryptionPrivateKey(atSign);
  }

  static Future<String?> getEncryptionPublicKey(String atSign) async {
    return await _keyChainManager.getEncryptionPublicKey(atSign);
  }

  static Future<String?> getAESKey(String atsign) async {
    return (await _keyChainManager.readAtsign(name: atsign))?.selfEncryptionKey;
  }

  static Future<String?> getSelfEncryptionKey(String atSign) async {
    return await _keyChainManager.getSelfEncryptionAESKey(atSign);
  }

  static Future<String?> getAtSign() async {
    // await _keyChainManager.initialSetup(useSharedStorage: false);
    return await _keyChainManager.getAtSign();
  }

  static Future<List<String>?> getAtsignList() async {
    return await _keyChainManager.getAtSignListFromKeychain();
  }

  static Future<void> resetAtSignFromKeychain(String atsign) async {
    await _keyChainManager.resetAtSignFromKeychain(atsign);
  }

  static Future<void> deleteAtSignFromKeychain(String atsign) async {
    await _keyChainManager.deleteAtSignFromKeychain(atsign);
  }

  static Future<bool> makeAtSignPrimary(String atsign) async {
    var atSignWithStatus = await getAtsignsWithStatus();
    if (atSignWithStatus[atsign]!) {
      return false;
    }
    return await _keyChainManager.makeAtSignPrimary(atsign);
  }

  static Future<Map<String, bool?>> getAtsignsWithStatus() async {
    return await _keyChainManager.getAtsignsWithStatus();
  }

  static Future<Map<String, String>> getEncryptedKeys(String atsign) async {
    var aesEncryptedKeys = {};
    // encrypt pkamPublicKey with AES key
    var pkamPublicKey = await getPkamPublicKey(atsign);
    var aesEncryptionKey = await getAESKey(atsign);
    var encryptedPkamPublicKey =
        EncryptionUtil.encryptValue(pkamPublicKey!, aesEncryptionKey!);
    aesEncryptedKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE] =
        encryptedPkamPublicKey;

    // encrypt pkamPrivateKey with AES key
    var pkamPrivateKey = await getPkamPrivateKey(atsign);
    var encryptedPkamPrivateKey =
        EncryptionUtil.encryptValue(pkamPrivateKey!, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE] =
        encryptedPkamPrivateKey;

    // encrypt encryption public key with AES key
    var encryptionPublicKey = await getEncryptionPublicKey(atsign);
    var encryptedEncryptionPublicKey =
        EncryptionUtil.encryptValue(encryptionPublicKey!, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE] =
        encryptedEncryptionPublicKey;

    // encrypt encryption private key with AES key
    var encryptionPrivateKey = await getEncryptionPrivateKey(atsign);
    var encryptedEncryptionPrivateKey =
        EncryptionUtil.encryptValue(encryptionPrivateKey!, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE] =
        encryptedEncryptionPrivateKey;

    // store  self encryption key as it is.This will be same as AES key in key zip file
    var selfEncryptionKey = await getSelfEncryptionKey(atsign);
    aesEncryptedKeys[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE] =
        selfEncryptionKey;
    return Map<String, String>.from(aesEncryptedKeys);
  }
}
