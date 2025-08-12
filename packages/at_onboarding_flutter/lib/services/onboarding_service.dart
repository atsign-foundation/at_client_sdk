import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_app_constants.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_response_status.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';

/// Service to handle onboarding flow
class OnboardingService {
  static final OnboardingService _singleton = OnboardingService._internal();

  OnboardingService._internal();

  factory OnboardingService.getInstance() {
    return _singleton;
  }

  KeyChainManager keyChainManager = KeyChainManager.getInstance();
  AtStatusImpl atStatusImpl =
      AtStatusImpl(rootUrl: AtOnboardingConstants.serverDomain);
  final AtSignLogger _logger = AtSignLogger('Onboarding Service');

  // NOTE: The atClientServiceMap which contains the "AtClientService" instance as a value is used by the mobile apps.
  // Hence marking as deprecated without removing.
  @Deprecated(
      'The AtClientService will be replaced with AtAuthService. Use AtClientManager.getInstance() for AtClientManager instance.')
  //ignore: deprecated_export_use
  Map<String?, AtClientService> atClientServiceMap =
      //ignore: deprecated_export_use
      <String?, AtClientService>{};

  String? _atsign;
  AtClientPreference _atClientPreference = AtClientPreference();

  String? _namespace;
  Widget? _applogo;
  bool? _isPkam;
  late Function onboardFunc;

  ServerStatus? serverStatus;

  set setLogo(Widget? logo) => _applogo = logo;

  Widget? get logo => _applogo;

  bool? get isPkam => _isPkam;

  set setAtClientPreference(AtClientPreference preference) {
    _atClientPreference = preference
      ..cramSecret = null
      ..privateKey = null;
  }

  AtClientPreference get atClientPreference => _atClientPreference;

  set namespace(String namespace) => _namespace = namespace;

  String? get appNamespace => _namespace;

  set setAtsign(String? atsign) {
    atsign = formatAtSign(atsign);
    _atsign = atsign;
  }

  String? get currentAtsign => _atsign;

  // next route set from using app
  Widget? _nextScreen;

  set setNextScreen(Widget? nextScreen) {
    _nextScreen = nextScreen;
  }

  Widget? fistTimeAuthScreen;

  Widget? get nextScreen => _nextScreen;

  /// Fetches atsign from device keychain.
  Future<String?> getAtSign() async {
    return keyChainManager.getAtSign();
  }

  ///
  Future<bool?> isUsingSharedStorage() async {
    final result = await keyChainManager.isUsingSharedStorage();
    return result;
  }

  ///Call this function before start onboarding
  Future<void> initialSetup({required bool usingSharedStorage}) async {
    await keyChainManager.initialSetup(useSharedStorage: usingSharedStorage);
  }

  /// To register for a new enrollment request
  Future<AtEnrollmentResponse> enroll(
      String atSign, EnrollmentRequest enrollmentRequest) async {
    AtAuthService authService =
        AtClientMobile.authService(atSign, atClientPreference);
    return authService.enroll(enrollmentRequest);
  }

  /// Returns `true` if authentication is successful for the existing atsign in device.
  Future<bool> onboard(
      {String? cramSecret, AtOnboardingRequest? atOnboardingRequest}) async {
    _atsign ??= await getAtSign();
    if (_atsign == null || _atsign!.isEmpty) {
      _logger.severe('atSign is not found');
      throw OnboardingStatus.ATSIGN_NOT_FOUND;
    }
    AtAuthService authService =
        AtClientMobile.authService(_atsign!, atClientPreference);
    bool isAtSignOnboarded = await authService.isOnboarded(_atsign!);
    // If atSign is onboarded, authenticate the atSign. Else onboard the atSign.
    if (isAtSignOnboarded) {
      AtAuthRequest atAuthRequest = AtAuthRequest(_atsign!);
      AtAuthResponse atAuthResponse =
          await authService.authenticate(atAuthRequest);
      return atAuthResponse.isSuccessful;
    }
    var onboardingResponse = await authService.onboard(
        AtOnboardingRequest(_atsign!)
          ..appName = (atOnboardingRequest != null &&
                  atOnboardingRequest.appName != null)
              ? atOnboardingRequest.appName
              : 'system'
          ..deviceName = (atOnboardingRequest != null &&
                  atOnboardingRequest.deviceName != null)
              ? atOnboardingRequest.deviceName
              : 'default-device',
        cramSecret: cramSecret);
    _logger.finer('onboardingResponse: $onboardingResponse');
    if (onboardingResponse.isSuccessful) {
      // Initializing "AtClientService" and adding to it map for backward compatibility.
      // Invoke init() method to initialize AtClient and AtLookup instances in atClientService.
      // ignore: deprecated_member_use, deprecated_export_use
      AtClientService atClientService = AtClientService();
      // ignore: deprecated_export_use
      // ignore: deprecated_member_use_from_same_package
      atClientServiceMap.putIfAbsent(_atsign, () => atClientService);
    }
    return onboardingResponse.isSuccessful;
  }

  /// Returns `false` if fails in authenticating [atsign] with [cramSecret]/[privateKey].
  /// Throws Exception if atsign is null.
  Future<AtOnboardingResponseStatus> authenticate(String? atsign,
      {String? cramSecret,
      String? jsonData,
      String? decryptKey,
      OnboardingStatus? status}) async {
    _isPkam = false;
    atsign = formatAtSign(atsign);
    if (atsign == null) {
      throw 'atSign cannot be null';
    }
    Completer<AtOnboardingResponseStatus> c =
        Completer<AtOnboardingResponseStatus>();
    try {
      serverStatus = await checkAtSignServerStatus(atsign);
      if (serverStatus != ServerStatus.teapot &&
          serverStatus != ServerStatus.activated) {
        c.complete(AtOnboardingResponseStatus.serverNotReached);
        if (cramSecret == null) {
          _isPkam = true;
        }
        return c.future;
      }
      AtAuthService atAuthService =
          AtClientMobile.authService(atsign, atClientPreference);
      _atClientPreference.cramSecret = cramSecret;
      if (cramSecret != null) {
        _atClientPreference.privateKey = null;
      }

      AtAuthRequest atAuthRequest = AtAuthRequest(atsign)
        ..rootDomain = _atClientPreference.rootDomain
        ..rootPort = _atClientPreference.rootPort;

      if (jsonData != null) {
        atAuthRequest.encryptedKeysMap = jsonDecode(jsonData);
      }

      AtAuthResponse atAuthResponse =
          await atAuthService.authenticate(atAuthRequest);
      if (atAuthResponse.isSuccessful) {
        _atsign = atsign;
        // Initializing "AtClientService" and adding to it map for backward compatibility.
        // Invoke init() method to initialize AtClient and AtLookup instances in atClientService.
        // ignore: deprecated_member_use, deprecated_export_use
        AtClientService atClientService = AtClientService();
        // ignore: deprecated_export_use
        // ignore: deprecated_member_use_from_same_package
        atClientServiceMap.putIfAbsent(_atsign, () => atClientService);
        c.complete(AtOnboardingResponseStatus.authSuccess);
      }
    } catch (e) {
      _logger.severe('error in authenticating =>  ${e.toString()}');
      if (e == AtOnboardingResponseStatus.timeOut) {
        c.completeError(e);
      } else {
        c.completeError(e.runtimeType == OnboardingStatus
            ? e
            : AtOnboardingResponseStatus.authFailed);
      }
    }
    return c.future;
  }

  /// Fetches privatekey for [atsign] from device keychain.
  Future<String?> getPrivateKey(String atsign) async {
    return await KeyChainManager.getInstance().getPkamPrivateKey(atsign);
  }

  /// Fetches publickey for [atsign] from device keychain.
  Future<String?> getPublicKey(String atsign) async {
    return await KeyChainManager.getInstance().getPkamPublicKey(atsign);
  }

  /// Fetches AESkey for [atsign] from device keychain.
  Future<String?> getAESKey(String atsign) async {
    return KeyChainManager.getInstance().getSelfEncryptionAESKey(atsign);
  }

  /// Fetches encryption keys for [atsign] from device keychain.
  Future<Map<String, String?>> getEncryptedKeys(String atsign) async {
    Map<String, String?> result =
        await KeyChainManager.getInstance().getEncryptedKeys(atsign);
    result[atsign] = await getAESKey(atsign);
    return result;
  }

  /// Returns null if [atsign] is null else the formatted [atsign].
  /// [atsign] must be non-null.
  String? formatAtSign(String? atsign) {
    if (atsign == null || atsign == '') {
      return null;
    }
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    atsign = !atsign.startsWith('@') ? '@$atsign' : atsign;
    return atsign;
  }

  Future<bool> isExistingAtsign(String? atsign) async {
    if (atsign == null) {
      return false;
    }
    atsign = formatAtSign(atsign);
    List<String> atSignsList = await getAtsignList();
    ServerStatus? status = await checkAtSignServerStatus(atsign!).timeout(
        Duration(seconds: AtOnboardingConstants.responseTimeLimit),
        onTimeout: () => throw AtOnboardingResponseStatus.timeOut);
    bool isExist =
        atSignsList.isNotEmpty ? atSignsList.contains(atsign) : false;
    if (status == ServerStatus.teapot) {
      isExist = false;
    }
    return isExist;
  }

  /// returns the list of all onboarded atsigns
  Future<List<String>> getAtsignList() async {
    List<String> atSignsList =
        await keyChainManager.getAtSignListFromKeychain();
    return atSignsList;
  }

  Future<ServerStatus?> checkAtSignServerStatus(String atsign) async {
    AtStatus status = await atStatusImpl.get(atsign);
    return status.serverStatus;
  }

  /// Returns the status of an atsign
  Future<AtSignStatus?> checkAtsignStatus({String? atsign}) async {
    atsign = atsign ?? _atsign;
    if (atsign == null) {
      return null;
    }
    atsign = formatAtSign(atsign);
    AtStatus status = await atStatusImpl.get(atsign!);
    return status.status();
  }

  /// Function to make the atsign passed as primary
  Future<bool> changePrimaryAtsign({required String atsign}) async {
    final result = await keyChainManager.makeAtSignPrimary(atsign);
    if (result == true) {
      setAtsign = atsign;
    }
    return result;
  }

  /// enables sharing onboarded atSign with multiple atApps
  /// it is only supported for macOS, windows platforms.
  Future<bool> enableUsingSharedStorage() async {
    final result = await keyChainManager.enableUsingSharedStorage();
    return result;
  }

  /// disables sharing onboarded atSign with multiple atApps
  Future<bool> disableUsingSharedStorage() async {
    final result = await keyChainManager.disableUsingSharedStorage();
    return result;
  }
}
