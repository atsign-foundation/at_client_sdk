import 'dart:convert';
import 'dart:core';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_client_auth.dart';
import 'package:at_client_mobile/src/auth_constants.dart';
import 'package:at_client_mobile/src/onboarding_status.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_client/src/manager/sync_manager_impl.dart';

class AtClientService {
  final AtSignLogger _logger = AtSignLogger('AtClientService');
  AtClientImpl atClient;
  AtClientAuthenticator _atClientAuthenticator;
  AtLookupImpl atLookUp;
  OnboardingStatus _status;
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

  // Will create at client instance for a given atSign and perform cram+pkam auth to the server.
  // if pkam is successful, encryption keys will be set for the user./// Will create at client instance for a given atSign.
  Future<bool> _init(String atSign, AtClientPreference preference) async {
    _atClientAuthenticator ??= AtClientAuthenticator();
    await AtClientImpl.createClient(atSign, preference.namespace, preference);
    atClient = await AtClientImpl.getClient(atSign);
    atLookUp = atClient.getRemoteSecondary().atLookUp;
    if (preference.outboundConnectionTimeout != null &&
        preference.outboundConnectionTimeout > 0) {
      atClient.getRemoteSecondary().atLookUp.outboundConnectionTimeout =
          preference.outboundConnectionTimeout;
    }
    _atClientAuthenticator.atLookUp = atClient.getRemoteSecondary().atLookUp;
    if (preference.privateKey != null) {
      _atClientAuthenticator.atLookUp.privateKey = preference.privateKey;
      atClient.getRemoteSecondary().atLookUp.privateKey = preference.privateKey;
    }
    return true;
  }

  Future<String> getPkamPrivateKey(String atSign) async {
    var pkamPrivateKey = await _keyChainManager.getPkamPrivateKey(atSign);
    return pkamPrivateKey;
  }

  Future<String> getPkamPublicKey(String atSign) async {
    return await _keyChainManager.getPkamPublicKey(atSign);
  }

  Future<String> getEncryptionPrivateKey(String atSign) async {
    return await _keyChainManager.getEncryptionPrivateKey(atSign);
  }

  Future<String> getEncryptionPublicKey(String atSign) async {
    return await _keyChainManager.getEncryptionPublicKey(atSign);
  }

  Future<String> getAESKey(String atsign) async {
    return await _keyChainManager.getValue(
        atsign, KEYCHAIN_SELF_ENCRYPTION_KEY);
  }

  Future<String> getSelfEncryptionKey(String atSign) async {
    return await _keyChainManager.getSelfEncryptionAESKey(atSign);
  }

  Future<String> getAtSign() async {
    return await _keyChainManager.getAtSign();
  }

  Future<List<String>> getAtsignList() async {
    return await _keyChainManager.getAtSignListFromKeychain();
  }

  Future<void> resetAtSignFromKeychain(String atsign) async {
    return await _keyChainManager.resetAtSignFromKeychain(atsign);
  }

  Future<void> deleteAtSignFromKeychain(String atsign) async {
    return await _keyChainManager.deleteAtSignFromKeychain(atsign);
  }

  Future<bool> makeAtSignPrimary(String atsign) async {
    var atSignWithStatus = await getAtsignsWithStatus();
    if (atSignWithStatus[atsign]) {
      return false;
    }
    return await _keyChainManager.makeAtSignPrimary(atsign);
  }

  Future<Map<String, bool>> getAtsignsWithStatus() async {
    return await _keyChainManager.getAtsignsWithStatus();
  }

  Future<Map<String, String>> getEncryptedKeys(String atsign) async {
    var aesEncryptedKeys = {};
    // encrypt pkamPublicKey with AES key
    var pkamPublicKey = await getPkamPublicKey(atsign);
    var aesEncryptionKey = await getAESKey(atsign);
    var encryptedPkamPublicKey =
        EncryptionUtil.encryptValue(pkamPublicKey, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE] =
        encryptedPkamPublicKey;

    // encrypt pkamPrivateKey with AES key
    var pkamPrivateKey = await getPkamPrivateKey(atsign);
    var encryptedPkamPrivateKey =
        EncryptionUtil.encryptValue(pkamPrivateKey, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE] =
        encryptedPkamPrivateKey;

    // encrypt encryption public key with AES key
    var encryptionPublicKey = await getEncryptionPublicKey(atsign);
    var encryptedEncryptionPublicKey =
        EncryptionUtil.encryptValue(encryptionPublicKey, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE] =
        encryptedEncryptionPublicKey;

    // encrypt encryption private key with AES key
    var encryptionPrivateKey = await getEncryptionPrivateKey(atsign);
    var encryptedEncryptionPrivateKey =
        EncryptionUtil.encryptValue(encryptionPrivateKey, aesEncryptionKey);
    aesEncryptedKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE] =
        encryptedEncryptionPrivateKey;

    // store  self encryption key as it is.This will be same as AES key in key zip file
    var selfEncryptionKey = await getSelfEncryptionKey(atsign);
    aesEncryptedKeys[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE] =
        selfEncryptionKey;
    return Map<String, String>.from(aesEncryptedKeys);
  }

  Future<bool> cramAuth(String cramSecret) async {
    return await _atClientAuthenticator.cramAuth(cramSecret);
  }

  Future<bool> pkamAuth(String privateKey) async {
    return await _atClientAuthenticator.pkamAuth(privateKey);
  }

  ///Returns `true` on persisting keys into keystore.
  Future<bool> persistKeys(String atSign) async {
    var pkamPrivateKey = await getPkamPrivateKey(atSign);

    var pkamPublicKey = await getPkamPublicKey(atSign);

    var encryptPrivateKey = await getEncryptionPrivateKey(atSign);

    var encryptPublicKey = await getEncryptionPublicKey(atSign);

    var selfEncryptionKey = await getSelfEncryptionKey(atSign);
    await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PUBLIC_KEY, pkamPublicKey);
    await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PRIVATE_KEY, pkamPrivateKey);
    await atClient
        .getLocalSecondary()
        .putValue(AT_ENCRYPTION_PRIVATE_KEY, encryptPrivateKey);
    var updateBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey'
      ..isPublic = true
      ..sharedBy = atSign
      ..value = encryptPublicKey;
    await atClient.getLocalSecondary().executeVerb(updateBuilder, sync: true);

    await atClient
        .getLocalSecondary()
        .putValue('privatekey:self_encryption_key', selfEncryptionKey);
    var result = await _getKeysFromLocalSecondary(atSign);

    return result;
  }

  Future<bool> _getKeysFromLocalSecondary(String atsign) async {
    var pkamPublicKey = await atClient.getLocalSecondary().getPublicKey();
    if (pkamPublicKey == null) {
      throw (OnboardingStatus.PKAM_PUBLIC_KEY_NOT_FOUND);
    }
    var pkamPrivateKey = await atClient.getLocalSecondary().getPrivateKey();
    if (pkamPrivateKey == null) {
      throw (OnboardingStatus.PKAM_PRIVATE_KEY_NOT_FOUND);
    }
    var encryptPrivateKey =
        await atClient.getLocalSecondary().getEncryptionPrivateKey();
    if (encryptPrivateKey == null) {
      throw (OnboardingStatus.ENCRYPTION_PRIVATE_KEY_NOT_FOUND);
    }
    var encryptPublicKey =
        await atClient.getLocalSecondary().getEncryptionPublicKey(atsign);
    if (encryptPublicKey == null) {
      throw (OnboardingStatus.ENCRYPTION_PUBLIC_KEY_NOT_FOUND);
    }

    var encryptSelfKey =
        await atClient.getLocalSecondary().getEncryptionSelfKey();
    if (encryptSelfKey == null) {
      throw (OnboardingStatus.SELF_ENCRYPTION_KEY_NOT_FOUND);
    }
    return false;
  }

  ///Returns `true` on successfully authenticating [atsign] with [cramSecret]/[privateKey].
  /// if pkam is successful, encryption keys will be set for the user.
  Future<bool> authenticate(
      String atsign, AtClientPreference atClientPreference,
      {OnboardingStatus status, String jsonData, String decryptKey}) async {
    if (atClientPreference.cramSecret == null) {
      atsign = _formatAtSign(atsign);
      if (atsign == null) {
        return false;
      }
      await _decodeAndStoreToKeychain(atsign, jsonData, decryptKey);
      atClientPreference.privateKey = await getPkamPrivateKey(atsign);
    }
    var result = await _init(atsign, atClientPreference);
    if (!result) {
      return result;
    }
    if (_status != OnboardingStatus.ACTIVATE &&
        status != OnboardingStatus.ACTIVATE.toString().split('.')[1]) {
      await _sync(atClientPreference, atsign);
    }
    result = await _atClientAuthenticator.performInitialAuth(
      atsign,
      cramSecret: atClientPreference.cramSecret,
      pkamPrivateKey: atClientPreference.privateKey,
    );
    if (result) {
      var privateKey = atClientPreference.privateKey ??=
          await _keyChainManager.getPkamPrivateKey(atsign);
      _atClientAuthenticator.atLookUp.privateKey = privateKey;
      atClient.getRemoteSecondary().atLookUp.privateKey = privateKey;
      await _sync(atClientPreference, atsign);
      await persistKeys(atsign);
      try {
        await _migrateOldSelfKeys();
      } on Exception catch (e) {
        _logger
            .severe('Exception while migrating old self keys: ${e.toString()}');
      }
    }
    return result;
  }

  Future<void> _decodeAndStoreToKeychain(
      String atsign, String jsonData, String decryptKey) async {
    var extractedjsonData = jsonDecode(jsonData);

    var pkamPublicKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE],
        decryptKey);

    var pkamPrivateKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE],
        decryptKey);
    await _keyChainManager.storePkamKeysToKeychain(atsign,
        privateKey: pkamPrivateKey, publicKey: pkamPublicKey);

    var encryptionPublicKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE],
        decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY, encryptionPublicKey);

    var encryptionPrivateKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE],
        decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PRIVATE_KEY, encryptionPrivateKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_SELF_ENCRYPTION_KEY, decryptKey);
  }

  ///Returns `true` on successfully completing onboarding.
  /// Throws [ATSIGN_NOT_FOUND] exception if atsign not found.
  /// Throws [PRIVATE_KEY_NOT_FOUND] exception if privatekey not found.
  Future<bool> onboard(
      {AtClientPreference atClientPreference, String atsign}) async {
    _atClientAuthenticator = AtClientAuthenticator();
    if (atsign == null || atsign == '') {
      atsign = await _keyChainManager.getAtSign();
    } else {
      atsign = _formatAtSign(atsign);
    }
    if (atsign == null || atsign == '') {
      _logger.severe('Atsign not found');
      throw OnboardingStatus.ATSIGN_NOT_FOUND;
    }
    var privateKey = atClientPreference.privateKey;
    if (privateKey == null || privateKey == '') {
      privateKey = await _keyChainManager.getPkamPrivateKey(atsign);
    }
    if (privateKey == null || privateKey == '') {
      _logger.severe('PrivateKey not found');
      throw OnboardingStatus.PRIVATE_KEY_NOT_FOUND;
      // return null;
    }
    atClientPreference.privateKey = privateKey;
    // atClientPreference.namespace != null
    // ? await _init(atsign, atClientPreference, namespace: namespace)
    await _init(atsign, atClientPreference);
    var keyRestorePolicyStatus = await getKeyRestorePolicy(atsign);
    if (keyRestorePolicyStatus == OnboardingStatus.ACTIVATE ||
        keyRestorePolicyStatus == OnboardingStatus.RESTORE) {
      _status = keyRestorePolicyStatus;
      throw (keyRestorePolicyStatus);
    }
    //no need of having pkam auth as unauth error can be thrown by keypolicy.
    var result = await pkamAuth(privateKey);
    if (result) await _sync(atClientPreference, atsign);
    try {
      await _migrateOldSelfKeys();
    } on Exception catch (e) {
      _logger
          .severe('Exception while migrating old self keys: ${e.toString()}');
    }
    return result;
  }

  Future<OnboardingStatus> getKeyRestorePolicy(String atSign) async {
    var serverEncryptionPublicKey = await _getServerEncryptionPublicKey(atSign);
    var localEncryptionPublicKey =
        await _keyChainManager.getValue(atSign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY);
    _logger.finer('local encryption public key:${localEncryptionPublicKey}');
    _logger.finer(
        'server encryption public key get result:${serverEncryptionPublicKey}');
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

  Future<void> _sync(AtClientPreference preference, String atSign) async {
    if ((preference.privateKey != null || preference.cramSecret != null) &&
        preference.syncStrategy != null) {
      var _syncManager = SyncManagerImpl.getInstance().getSyncManager(atSign);
      _syncManager.init(atSign, preference, atClient.getRemoteSecondary(),
          atClient.getLocalSecondary());
      await _syncManager.sync(appInit: true, regex: preference.syncRegex);
    }
  }

  ///returns public key for [atsign] if found else returns null.
  Future<String> _getServerEncryptionPublicKey(String atsign) async {
    var command = 'lookup:publickey${atsign}\n';
    var result = await atLookUp.executeCommand(command);
    if (_isNullOrEmpty(result) || _isError(result)) {
      //checking for an authenticated connection
      command = 'llookup:public:publickey${atsign}\n';
      result = await atLookUp.executeCommand(command);
      if (_isNullOrEmpty(result) || _isError(result)) {
        return null;
      }
    }
    return result.replaceFirst('data:', '');
  }

  // @alice:shared_key@alice - previously this key was generated inside encryption service
  // and encrypted with public key. Now we use a single aes key to encrypt self keys as well as key pairs in key file
  void _migrateOldSelfKeys() async {
    var currentAtSign = atClient.currentAtSign;
    var isMigrated =
        await _keyChainManager.getValue(currentAtSign, 'selfKeysMigrated');
    if (isMigrated == 'true') {
      return;
    }

    //1. local lookup up self encryption key
    var metadata = Metadata()..namespaceAware = false;
    var atKey = AtKey()
      ..metadata = metadata
      ..sharedBy = currentAtSign
      ..sharedWith = currentAtSign
      ..key = AT_ENCRYPTION_SHARED_KEY;
    var selfKeyValue = await atClient.get(atKey);
    if (selfKeyValue == null || selfKeyValue.value == null) {
      _logger.severe('self encryption key is null. Skipping migration');
      return;
    }
    // if (selfKeyValue.metadata != null) {
    //old key. migrate data
    //decrypt the oldSelfKey with private key
    var encryptionPrivateKey =
        await atClient.getLocalSecondary().getEncryptionPrivateKey();
    var decryptedSelfKey =
        EncryptionUtil.decryptKey(selfKeyValue.value, encryptionPrivateKey);
    _logger.finer('decryptedSelfKey:${decryptedSelfKey}');
    var newAesKey =
        await _keyChainManager.getSelfEncryptionAESKey(currentAtSign);
    _logger.finer('newAesKey:${newAesKey}');
    var selfKeys = await atClient.getAtKeys(
        sharedWith: currentAtSign, sharedBy: currentAtSign);
    await Future.forEach(
        selfKeys,
        (atKey) => _encryptOldSelfKey(
            atKey, decryptedSelfKey, newAesKey, currentAtSign));
    // print('All keys are ')

    await _keyChainManager.putValue(currentAtSign, 'selfKeysMigrated', 'true');
    //delete old self encryption key from server
    var builder = DeleteVerbBuilder()
      ..sharedBy = currentAtSign
      ..sharedWith = currentAtSign
      ..atKey = AT_ENCRYPTION_SHARED_KEY;
    await atClient.getLocalSecondary().executeVerb(builder, sync: true);
    // } else {
    _logger.finer(
        'self keys already migrated. New aes key:${await _keyChainManager.getSelfEncryptionAESKey(currentAtSign)}');
    // }
  }

  void _encryptOldSelfKey(
      AtKey atKey, String oldSelfKey, String newAesKey, String atSign) async {
    if (atKey.key.contains(AT_SIGNING_PRIVATE_KEY) ||
        (atKey.sharedWith != null && atKey.sharedWith != atSign) ||
        atKey.metadata.isPublic) {
      //skip signing private key, keys shared with other users and public keys
      return;
    }
    try {
      //#TODO remove the logger statements before pushing to prod
      //1. get the existing value encrypted with previous key
      var existingEncryptedAtValue = await atClient.get(atKey);
      if (existingEncryptedAtValue == null) {
        _logger
            .severe('_encryptOldSelfKey value not found for key ${atKey.key}');
        return;
      }
      var existingEncryptedValue = existingEncryptedAtValue.value;
      //2. decrypt the value
      var decryptedValue =
          EncryptionUtil.decryptValue(existingEncryptedValue, oldSelfKey);
      _logger.finer('decryptedValue:${decryptedValue}');
      //3. get the new AES key

      //4. encrypt the value with new AES key
      var newEncryptedValue =
          EncryptionUtil.encryptValue(decryptedValue, newAesKey);
      //5. update the new value and sync to server
      await atClient.put(atKey, newEncryptedValue);
    } on Exception catch (e) {
      _logger.severe(
          'Exception migrating key : ${atKey.key} exception: ${e.toString()}');
    }
  }

  bool _isNullOrEmpty(String key) {
    if (key == null) {
      return true;
    }
    key = key.replaceFirst('data:', '');
    if (key == 'null' || key.isEmpty) {
      return true;
    }
    return false;
  }

  bool _isError(String key) {
    return key != null ? key.contains('error') : false;
  }

  ///Returns null if [atsign] is null else the formatted [atsign].
  ///[atsign] must be non-null.
  String _formatAtSign(String atsign) {
    if (atsign == null || atsign == '') {
      return null;
    }
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    atsign = !atsign.startsWith('@') ? '@' + atsign : atsign;
    return atsign;
  }
}

class BackupKeyConstants {
  static const String PKAM_PUBLIC_KEY_FROM_KEY_FILE = 'aesPkamPublicKey';
  static const String PKAM_PRIVATE_KEY_FROM_KEY_FILE = 'aesPkamPrivateKey';
  static const String ENCRYPTION_PUBLIC_KEY_FROM_FILE = 'aesEncryptPublicKey';
  static const String ENCRYPTION_PRIVATE_KEY_FROM_FILE = 'aesEncryptPrivateKey';
  static const String SELF_ENCRYPTION_KEY_FROM_FILE = 'selfEncryptionKey';
}
