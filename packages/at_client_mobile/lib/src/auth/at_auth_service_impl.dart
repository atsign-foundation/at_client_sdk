import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class AtAuthServiceImpl implements AtAuthService {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');

  AtServiceFactory? atServiceFactory;
  AtClient? _atClient;
  AtLookUp? _atLookUp;

  final String _atSign;
  final AtClientPreference _atClientPreference;

  final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  AtClientManager atClientManager = AtClientManager.getInstance();
  AtAuth atAuth = AtAuthImpl();

  AtAuthServiceImpl(this._atSign, this._atClientPreference);

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    // If the user does not provide the keys data then fetch for the keys in the
    // keychain manager.
    // User provides keys data either by
    //  - 1. atAuthRequest.atKeysFilePath - The file path of .atKeys file.
    //  - 2. atAuthRequest.atAuthKeys - The AtAuthKeys instance which contains the keys
    //  - 3. atAuthRequest.encryptedKeysMap - Provide the contents of atKeys file which
    //    contains keys in encrypted format
    if (atAuthRequest.atKeysFilePath == null &&
        atAuthRequest.atAuthKeys == null &&
        atAuthRequest.encryptedKeysMap == null) {
      _logger.info(
          'Fetching the keys from Keychain Manager of atSign: ${atAuthRequest.atSign}');
      atAuthRequest.atAuthKeys = await _fetchKeysFromKeychainManager();
    }
    // Invoke authenticate method in AtAuth package.
    AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
    // If authentication is failed, return the atAuthResponse. Do nothing.
    if (atAuthResponse.isSuccessful == false) {
      return atAuthResponse;
    }
    // If authentication is successful, initialize AtClient instance.
    await _init(atAuth.atChops!, enrollmentId: atAuthResponse.enrollmentId);
    // When an atSign is authenticated via the .atKeys on a new device, the keys
    // will not be present in keychain manager. Add keys to key-chain manager.
    AtsignKey? atSignKey = await _keyChainManager.readAtsign(name: _atSign);
    if (atSignKey == null) {
      await _storeToKeyChainManager(_atSign, atAuthResponse.atAuthKeys);
    }
    return atAuthResponse;
  }

  Future<AtAuthKeys> _fetchKeysFromKeychainManager() async {
    AtsignKey? atSignKey = await _keyChainManager.readAtsign(name: _atSign);
    if (atSignKey == null) {
      throw AtAuthenticationException(
          'Failed to authenticate. Keys not found in Keychain manager for atSign: $_atSign');
    }

    AtAuthKeys atAuthKeys = AtAuthKeys()
      ..apkamPrivateKey = atSignKey.pkamPrivateKey
      ..apkamPublicKey = atSignKey.pkamPublicKey
      ..defaultEncryptionPrivateKey = atSignKey.encryptionPrivateKey
      ..defaultEncryptionPublicKey = atSignKey.encryptionPublicKey
      ..defaultSelfEncryptionKey = atSignKey.selfEncryptionKey
      ..apkamSymmetricKey = atSignKey.apkamSymmetricKey
      ..enrollmentId = atSignKey.enrollmentId;

    return atAuthKeys;
  }

  @override
  Future<bool> isOnboarded(String atSign) async {
    AtsignKey? atsignKey = await _keyChainManager.readAtsign(name: atSign);
    if (atsignKey == null) {
      return false;
    }
    if (atsignKey.encryptionPublicKey == null ||
        atsignKey.encryptionPublicKey!.isEmpty) {
      return false;
    }
    return true;
  }

  @override
  Future<AtOnboardingResponse> onboard(AtOnboardingRequest atOnboardingRequest,
      {String? cramSecret}) async {
    if (cramSecret == null || cramSecret.isEmpty) {
      throw AtException(
          'CRAM Secret cannot be null or empty for atSign: $_atSign');
    }
    AtOnboardingResponse atOnboardingResponse =
        await atAuth.onboard(atOnboardingRequest, cramSecret);
    // If onboarding is not successful, return the onboarding response
    // with the isSuccessful set to false.
    if (!atOnboardingResponse.isSuccessful) {
      return atOnboardingResponse;
    }
    if (atAuth.atChops == null) {
      throw AtAuthenticationException(
          'Failed to onboard atSign: $_atSign. AtChops is not initialized in AtAuth Package');
    }
    await _init(atAuth.atChops!,
        enrollmentId: atOnboardingResponse.enrollmentId);
    await _storeToKeyChainManager(
        atOnboardingResponse.atSign, atOnboardingResponse.atAuthKeys);
    await _persistKeysLocalSecondary(atOnboardingResponse.atAuthKeys);
    return atOnboardingResponse;
  }

  /// Stores the atKeys to Key-Chain Manager.
  Future<void> _storeToKeyChainManager(
      String atSign, AtAuthKeys? atAuthKeys) async {
    if (atAuthKeys == null) {
      throw AtException(
          'Failed to store keys in Keychain manager for atSign: $_atSign. AtAuthKeys instance is null');
    }

    var atSignItem = await _keyChainManager.readAtsign(name: atSign) ??
        AtsignKey(atSign: atSign);
    atSignItem = atSignItem.copyWith(
        pkamPrivateKey: atAuthKeys.apkamPrivateKey,
        pkamPublicKey: atAuthKeys.apkamPublicKey,
        encryptionPrivateKey: atAuthKeys.defaultEncryptionPrivateKey,
        encryptionPublicKey: atAuthKeys.defaultEncryptionPublicKey,
        selfEncryptionKey: atAuthKeys.defaultSelfEncryptionKey,
        apkamSymmetricKey: atAuthKeys.apkamSymmetricKey,
        enrollmentId: atAuthKeys.enrollmentId);

    await _keyChainManager.storeAtSign(atSign: atSignItem);
  }

  Future<void> _persistKeysLocalSecondary(AtAuthKeys? atAuthKeys) async {
    if (atAuthKeys == null) {
      throw AtException(
          'Failed to store keys in Keychain manager for atSign: $_atSign. AtAuthKeys instance is null');
    }

    await _atClient!
        .getLocalSecondary()!
        .putValue(AtConstants.atPkamPublicKey, atAuthKeys.apkamPublicKey!);

    // pkam private will not be available in case of secure element
    if (atAuthKeys.apkamPrivateKey != null) {
      await _atClient!
          .getLocalSecondary()!
          .putValue(AtConstants.atPkamPrivateKey, atAuthKeys.apkamPrivateKey!);
    }

    await _atClient!.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionPrivateKey,
        atAuthKeys.defaultEncryptionPrivateKey!);

    var updateBuilder = UpdateVerbBuilder()
      ..atKey = 'publickey'
      ..isPublic = true
      ..sharedBy = _atSign
      ..value = atAuthKeys.defaultEncryptionPublicKey
      ..metadata.ttr = -1;
    await _atClient!
        .getLocalSecondary()!
        .executeVerb(updateBuilder, sync: true);

    await _atClient!.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionSelfKey, atAuthKeys.defaultSelfEncryptionKey!);
  }

  Future<void> _init(AtChops atChops, {String? enrollmentId}) async {
    await _initAtClient(atChops, enrollmentId: enrollmentId);
    _atLookUp!.atChops = atChops;
    _atClient!.atChops = atChops;
  }

  Future<void> _initAtClient(AtChops atChops, {String? enrollmentId}) async {
    AtClientManager atClientManager = AtClientManager.getInstance();
    await atClientManager.setCurrentAtSign(
        _atSign, _atClientPreference.namespace, _atClientPreference,
        atChops: atChops,
        serviceFactory: atServiceFactory,
        enrollmentId: enrollmentId);
    // ??= to support mocking
    _atLookUp ??= atClientManager.atClient.getRemoteSecondary()?.atLookUp;
    _atLookUp?.enrollmentId = enrollmentId;
    _atLookUp?.signingAlgoType = _atClientPreference.signingAlgoType;
    _atLookUp?.hashingAlgoType = _atClientPreference.hashingAlgoType;
    _atClient ??= atClientManager.atClient;
  }
}
