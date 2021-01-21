import 'dart:convert';
import 'dart:core';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_client_auth.dart';
import 'package:at_client_mobile/src/auth_constants.dart';
import 'package:at_client_mobile/src/key_restore_status.dart';
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
  KeyRestoreStatus _status;
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

  Future<String> getPrivateKey(String atSign) async {
    var pkamPrivateKey = await _keyChainManager.getPrivateKey(atSign);
    return pkamPrivateKey;
  }

  Future<String> getPublicKey(String atSign) async {
    return await _keyChainManager.getPublicKey(atSign);
  }

  Future<String> getEncryptionPrivateKey(String atSign) async {
    return await _keyChainManager.getEncryptionPrivateKey(atSign);
  }

  Future<String> getEncryptionPublicKey(String atSign) async {
    return await _keyChainManager.getEncryptionPublicKey(atSign);
  }

  Future<String> getAESKey(String atsign) async {
    return await _keyChainManager.getValue(atsign, KEYCHAIN_AES_KEY);
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
    aesEncryptedKeys[BackupKeyConstants.AES_PKAM_PUBLIC_KEY] =
        await _keyChainManager.getValue(atsign, KEYCHAIN_AES_PKAM_PUBLIC_KEY);
    aesEncryptedKeys[BackupKeyConstants.AES_PKAM_PRIVATE_KEY] =
        await _keyChainManager.getValue(atsign, KEYCHAIN_AES_PKAM_PRIVATE_KEY);
    aesEncryptedKeys[BackupKeyConstants.AES_ENCRYPTION_PUBLIC_KEY] =
        await _keyChainManager.getValue(
            atsign, KEYCHAIN_AES_ENCRYPTION_PUBLIC_KEY);
    aesEncryptedKeys[BackupKeyConstants.AES_ENCRYPTION_PRIVATE_KEY] =
        await _keyChainManager.getValue(
            atsign, KEYCHAIN_AES_ENCRYPTION_PRIVATE_KEY);
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
    var pkamPrivateKey = await getPrivateKey(atSign);
    var pkamPublicKey = await getPublicKey(atSign);
    var encryptPrivateKey = await getEncryptionPrivateKey(atSign);
    var encryptPublicKey = await getEncryptionPublicKey(atSign);
    var result = await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PUBLIC_KEY, pkamPublicKey);
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PRIVATE_KEY, pkamPrivateKey);
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_ENCRYPTION_PRIVATE_KEY, encryptPrivateKey);
    var updateBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey'
      ..isPublic = true
      ..sharedBy = atSign
      ..value = encryptPublicKey;
    await atClient.getLocalSecondary().executeVerb(updateBuilder, sync: true);
    return result;
  }

  ///Returns `true` on successfully authenticating [atsign] with [cramSecret]/[privateKey].
  /// if pkam is successful, encryption keys will be set for the user.
  Future<bool> authenticate(
      String atsign, AtClientPreference atClientPreference,
      {String status, String jsonData, String decryptKey}) async {
    if (atClientPreference.cramSecret == null) {
      atsign = _formatAtSign(atsign);
      if (atsign == null) {
        return false;
      }
      await _decodeAndStoreToKeychain(atsign, jsonData, decryptKey);
      atClientPreference.privateKey = await getPrivateKey(atsign);
    }
    var result = await _init(atsign, atClientPreference);
    if (!result) {
      return result;
    }
    if (_status != KeyRestoreStatus.ACTIVATE &&
        status != KeyRestoreStatus.ACTIVATE.toString().split('.')[1]) {
      await _sync(atClientPreference, atsign);
    }
    result = await _atClientAuthenticator.performInitialAuth(
      atsign,
      cramSecret: atClientPreference.cramSecret,
      pkamPrivateKey: atClientPreference.privateKey,
      // status: _status ??
      //         status == KeyRestoreStatus.ACTIVATE.toString().split('.')[1]
      //     ? KeyRestoreStatus.ACTIVATE
      // : null
    );
    if (result) {
      var privateKey = atClientPreference.privateKey ??=
          await _keyChainManager.getPrivateKey(atsign);
      _atClientAuthenticator.atLookUp.privateKey = privateKey;
      atClient.getRemoteSecondary().atLookUp.privateKey = privateKey;
      await _sync(atClientPreference, atsign);
      await persistKeys(atsign);
    }
    return result;
  }

  Future<void> _decodeAndStoreToKeychain(
      String atsign, String jsonData, String decryptKey) async {
    var extractedjsonData = jsonDecode(jsonData);
    await _storeEncryptedKeysToKeychain(extractedjsonData, atsign);

    var publicKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.AES_PKAM_PUBLIC_KEY], decryptKey);

    var privateKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.AES_PKAM_PRIVATE_KEY], decryptKey);
    await _keyChainManager.storePkamKeysToKeychain(atsign,
        privateKey: privateKey, publicKey: publicKey);

    var aesEncryptPublicKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.AES_ENCRYPTION_PUBLIC_KEY],
        decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY, aesEncryptPublicKey);

    var aesEncryptPrivateKey = EncryptionUtil.decryptValue(
        extractedjsonData[BackupKeyConstants.AES_ENCRYPTION_PRIVATE_KEY],
        decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PRIVATE_KEY, aesEncryptPrivateKey);
    await _keyChainManager.putValue(atsign, KEYCHAIN_AES_KEY, decryptKey);
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
      throw ('ATSIGN_NOT_FOUND');
      // return null;
    }
    var privateKey = atClientPreference.privateKey;
    if (privateKey == null || privateKey == '') {
      privateKey = await _keyChainManager.getPrivateKey(atsign);
    }
    if (privateKey == null || privateKey == '') {
      _logger.severe('PrivateKey not found');
      throw ('PRIVATE_KEY_NOT_FOUND');
      // return null;
    }
    atClientPreference.privateKey = privateKey;
    // atClientPreference.namespace != null
    // ? await _init(atsign, atClientPreference, namespace: namespace)
    await _init(atsign, atClientPreference);
    var keyRestorePolicyStatus = await getKeyRestorePolicy(atsign);
    if (keyRestorePolicyStatus == KeyRestoreStatus.ACTIVATE ||
        keyRestorePolicyStatus == KeyRestoreStatus.RESTORE) {
      _status = keyRestorePolicyStatus;
      throw ('${keyRestorePolicyStatus.toString().split('.')[1]}');
    }
    //no need of having pkam auth as unauth error can be thrown by keypolicy.
    var result = await pkamAuth(privateKey);
    if (result) await _sync(atClientPreference, atsign);
    return result;
  }

  Future<KeyRestoreStatus> getKeyRestorePolicy(String atSign) async {
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
      return KeyRestoreStatus.ACTIVATE;
    } else if (!_isNullOrEmpty(serverEncryptionPublicKey) &&
        _isNullOrEmpty(localEncryptionPublicKey)) {
      return KeyRestoreStatus.RESTORE;
    } else if (_isNullOrEmpty(serverEncryptionPublicKey) &&
        !_isNullOrEmpty(localEncryptionPublicKey)) {
      return KeyRestoreStatus.SYNC_TO_SERVER;
    } else {
      //both keys not null
      if (serverEncryptionPublicKey == localEncryptionPublicKey) {
        return KeyRestoreStatus.REUSE;
      } else {
        return KeyRestoreStatus.RESTORE;
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

  Future<void> _storeEncryptedKeysToKeychain(var data, String atsign) async {
    await _keyChainManager.putValue(atsign, KEYCHAIN_AES_PKAM_PUBLIC_KEY,
        data[BackupKeyConstants.AES_PKAM_PUBLIC_KEY]);
    await _keyChainManager.putValue(atsign, KEYCHAIN_AES_PKAM_PRIVATE_KEY,
        data[BackupKeyConstants.AES_PKAM_PRIVATE_KEY]);
    await _keyChainManager.putValue(atsign, KEYCHAIN_AES_ENCRYPTION_PUBLIC_KEY,
        data[BackupKeyConstants.AES_ENCRYPTION_PUBLIC_KEY]);
    await _keyChainManager.putValue(atsign, KEYCHAIN_AES_ENCRYPTION_PRIVATE_KEY,
        data[BackupKeyConstants.AES_ENCRYPTION_PRIVATE_KEY]);
  }
}

class BackupKeyConstants {
  static const String AES_PKAM_PUBLIC_KEY = 'aesPkamPublicKey';
  static const String AES_PKAM_PRIVATE_KEY = 'aesPkamPrivateKey';
  static const String AES_ENCRYPTION_PUBLIC_KEY = 'aesEncryptPublicKey';
  static const String AES_ENCRYPTION_PRIVATE_KEY = 'aesEncryptPrivateKey';
}
