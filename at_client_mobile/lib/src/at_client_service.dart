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
import 'package:at_client/src/manager/sync_manager.dart';

class AtClientService {
  final AtSignLogger _logger = AtSignLogger('AtClientService');
  AtClientImpl atClient;
  AtClientAuthenticator _atClientAuthenticator;
  AtLookupImpl atLookUp;
  AtClientPreference _atClientPreference;
  KeyRestoreStatus _status;
  String _namespace;
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  final SyncManager _syncManager = SyncManager.getInstance();

  // Will create at client instance for a given atSign and perform cram+pkam auth to the server.
  // if pkam is successful, encryption keys will be set for the user./// Will create at client instance for a given atSign.
  Future<bool> _init(String atSign, AtClientPreference preference,
      {String namespace}) async {
    await AtClientImpl.createClient(atSign, namespace, preference);
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

  Future<Map<String, String>> getEncryptedKeys(String atsign) async {
    var aesEncryptedKeys = {};
    aesEncryptedKeys['aesPkamPublicKey'] =
        await _keyChainManager.getValue(atsign, KEYCHAIN_AES_PKAM_PUBLIC_KEY);
    aesEncryptedKeys['aesPkamPrivateKey'] =
        await _keyChainManager.getValue(atsign, KEYCHAIN_AES_PKAM_PRIVATE_KEY);
    aesEncryptedKeys['aesEncryptPublicKey'] = await _keyChainManager.getValue(
        atsign, KEYCHAIN_AES_ENCRYPTION_PUBLIC_KEY);
    aesEncryptedKeys['aesEncryptPrivateKey'] = await _keyChainManager.getValue(
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
  Future<bool> authenticate(String atsign,
      {String cramSecret,
      KeyRestoreStatus status,
      String jsonData,
      String decryptKey}) async {
    if (cramSecret == null) {
      await _decodeAndStoreToKeychain(atsign, jsonData, decryptKey);
      _atClientPreference.privateKey = await getPrivateKey(atsign);
    }
    _atClientPreference.cramSecret = cramSecret;
    var result =
        await _init(atsign, _atClientPreference, namespace: _namespace);
    if (!result) {
      return result;
    }
    if (_status != KeyRestoreStatus.ACTIVATE) {
      await _sync(_atClientPreference, atsign);
    }
    result = await _atClientAuthenticator.performInitialAuth(atsign,
        cramSecret: cramSecret,
        pkamPrivateKey: _atClientPreference.privateKey,
        status: _status);
    if (result) {
      var privateKey = _atClientPreference.privateKey ??=
          await _keyChainManager.getPrivateKey(atsign);
      _atClientAuthenticator.atLookUp.privateKey = privateKey;
      atClient.getRemoteSecondary().atLookUp.privateKey = privateKey;
      await _sync(_atClientPreference, atsign);
      await persistKeys(atsign);
    }
    return result;
  }

  Future<void> _decodeAndStoreToKeychain(
      String atsign, String jsonData, String decryptKey) async {
    var extractedjsonData = jsonDecode(jsonData);
    var publicKey = EncryptionUtil.decryptValue(
        extractedjsonData['aesPkamPublicKey'], decryptKey);
    var privateKey = EncryptionUtil.decryptValue(
        extractedjsonData['aesPkamPrivateKey'], decryptKey);
    await _keyChainManager.storeCredentialToKeychain(atsign,
        privateKey: privateKey, publicKey: publicKey);
    var aesEncryptPublicKey = EncryptionUtil.decryptValue(
        extractedjsonData['aesEncryptPublicKey'], decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PUBLIC_KEY, aesEncryptPublicKey);
    var aesEncryptPrivateKey = EncryptionUtil.decryptValue(
        extractedjsonData['aesEncryptPrivateKey'], decryptKey);
    await _keyChainManager.putValue(
        atsign, KEYCHAIN_ENCRYPTION_PRIVATE_KEY, aesEncryptPrivateKey);
    await _keyChainManager.putValue(atsign, KEYCHAIN_AES_KEY, decryptKey);
  }

  ///Returns `true` on successfully completing onboarding.
  /// Throws [ATSIGN_NOT_FOUND] exception if atsign not found.
  /// Throws [PRIVATE_KEY_NOT_FOUND] exception if privatekey not found.
  Future<bool> onboard(
      {AtClientPreference atClientPreference,
      String atsign,
      String namespace}) async {
    _atClientPreference = atClientPreference;
    _namespace = namespace;
    _atClientAuthenticator = AtClientAuthenticator();
    if (atsign == null || atsign == '') {
      atsign = await _keyChainManager.getAtSign();
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
    namespace != null
        ? await _init(atsign, atClientPreference, namespace: namespace)
        : await _init(atsign, atClientPreference);
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
      _syncManager.init(atSign, preference, atClient.getRemoteSecondary(),
          atClient.getLocalSecondary());
      await _syncManager.sync(appInit: true);
    }
  }

  ///returns public key for [atsign] if found else returns null.
  Future<String> _getServerEncryptionPublicKey(String atsign) async {
    var command = 'lookup:publickey${atsign}\n';
    var result = await atLookUp.executeCommand(command);
    if (_isNullOrEmpty(result) || _isError(result)) {
      return null;
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
}
