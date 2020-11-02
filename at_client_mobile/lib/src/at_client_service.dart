import 'dart:convert';
import 'dart:core';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_client_auth.dart';
import 'package:at_client_mobile/src/auth_constants.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_client/src/util/encryption_util.dart';

class AtClientService {
  final AtSignLogger _logger = AtSignLogger('AtClientService');
  AtClientImpl atClient;
  AtClientAuthenticator _atClientAuthenticator;
  AtLookUp atLookUp;
  AtClientPreference _atClientPreference;
  String _namespace;
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

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
    await atClient.getLocalSecondary().executeVerb(updateBuilder);
    return result;
  }

  ///Returns `true` on successfully authenticating [atsign] with [cramSecret]/[privateKey].
  /// if pkam is successful, encryption keys will be set for the user.
  Future<bool> authenticate(String atsign,
      {String cramSecret, String jsonData, String decryptKey}) async {
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
    result = await _atClientAuthenticator.performInitialAuth(atsign,
        cramSecret: cramSecret, pkamPrivateKey: _atClientPreference.privateKey);
    if (result) {
      var privateKey = _atClientPreference.privateKey ??=
          await _keyChainManager.getPrivateKey(atsign);
      _atClientAuthenticator.atLookUp.privateKey = privateKey;
      atClient.getRemoteSecondary().atLookUp.privateKey = privateKey;

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
    return await pkamAuth(privateKey);
  }
}
