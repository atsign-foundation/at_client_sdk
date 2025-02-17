import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/onboarding/models/environment.dart';
import 'package:at_client_mobile/src/onboarding/services/registrar_service.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_utils.dart';

/// {@template onboarding_service}
/// A service class for managing onboarding.
/// {@endtemplate}
class OnboardingService with AtClientBindings {
  /// {@macro onboarding_service}
  OnboardingService({required this.rootEnvironment});

  final RootEnvironment rootEnvironment;

  // ----- Required services and managers -----
  @override
  AtClient get atClient => AtClientManager.getInstance().atClient;

  @override
  final AtSignLogger logger = AtSignLogger('OnboardingService');

  final _keyChainManager = KeyChainManager.getInstance();

  // ----- Internal State -----

  AtServerStatus? _atStatus;

  void _setAtStatus(String rootDomain, int rootPort) {
    _atStatus = AtStatusImpl(rootUrl: rootDomain, rootPort: rootPort);
  }

  // TODO: Set this when we know the atSign
  String? _onboardingAtSign;

  set _setOnboardingAtsign(String atsign) {
    final formattedAtSign = AtUtils.fixAtSign(atsign);
    _onboardingAtSign = formattedAtSign;
  }

  AtClientPreference? _atClientPreference;

  AtAuthService? _atAuthService;

  void _setAtAuthService(String atSign, AtClientPreference atClientPreference) {
    _atAuthService = AtClientMobile.authService(
      atSign,
      atClientPreference,
    );
  }

  // What is required?
  // - Name of atsign
  // - Namespace -> available from AtClient
  // - AtClient Preferences so they can be set on the AtClient (or should this be expected to be done?)
  // - Root domain
  //
  // What is optional?
  // - CRAM secret
  // - Environment
  // - API Key

  // This will all need to be broken down into the different steps of onboarding
  // I guess onboarding is a fancy state machine

  // Note: Add asserts where needed to make sure state is as expected

  //? Might not be needed.
  // Potentially for shared storage?
  Future<void> init() async {}

  /// [atClientPreference] contains the CRAM secret (optional), namespace, and root server information.

  /// Login/Onboard the given [atSign]. This is to be called if the client knows the atsign in some way.
  ///
  /// This can be done using the keychain (default, and expected flow), CRAM secret (passed in the
  /// [atClientPreference]) or a [filePath] containing the secret keys.
  ///
  /// Will first use the file path if provided, then the CRAM secret if available, and finally the keychain.
  ///
  /// If [loginProgress] is provided, it will be used to report the progress of the login process.
  Future<LoginRequestResult> login({
    required String atSign,
    required AtClientPreference atClientPreference,
    String? filePath,
    StreamSink<AuthenticationStates>? loginProgress,
  }) async {
    loginProgress?.add(AuthenticationStates.loading);
    //? Do I need to _keyChainManager.initialSetup(useSharedStorage: true);
    _setOnboardingAtsign = atSign;
    _atClientPreference = atClientPreference;

    _setAtAuthService(atSign, atClientPreference);
    _setAtStatus(atClientPreference.rootDomain, atClientPreference.rootPort);

    if (filePath != null) {
      // Authenticate using the file path. Shouldn't check if the atsign is onboarded as it must be to get the keys
      // in the first place.
      logger.info('Authenticating using file path');
      final authRequest = AtAuthRequest(_onboardingAtSign!)
        ..rootDomain = _atClientPreference!.rootDomain
        ..rootPort = _atClientPreference!.rootPort
        ..atKeysFilePath = filePath;

      loginProgress?.add(AuthenticationStates.authenticating);
      final authResult = await _atAuthService!.authenticate(authRequest);

      if (authResult.isSuccessful) {
        logger.info('Authentication using file path successful');
        loginProgress?.add(AuthenticationStates.success);
        return LoginRequestResult.success;
      } else {
        logger.info('Authentication using file path failed');
        loginProgress?.add(AuthenticationStates.failure);
        return LoginRequestResult.error;
      }
    }

    // Checks if the crypto keys are in the keychain
    final isOnboarded = await _atAuthService!.isOnboarded(_onboardingAtSign!);
    logger.info('$_onboardingAtSign is onboarded: $isOnboarded');
    if (isOnboarded) {
      // Note: This method can also be used to authenticate with atKeys
      final authRequest = AtAuthRequest(_onboardingAtSign!)
        ..rootDomain = _atClientPreference!.rootDomain
        ..rootPort = _atClientPreference!.rootPort;
      final authResult = await _atAuthService!.authenticate(authRequest);
      if (authResult.isSuccessful) {
        return LoginRequestResult.success;
      } else {
        return LoginRequestResult.error;
      }
    } else {
      return LoginRequestResult.keysMissing;
    }
  }

  /// Registers a new atSign
  Future<void> register({
    required AtClientPreference atClientPreference,
  }) async {
    _atClientPreference = atClientPreference;
    _setAtStatus(atClientPreference.rootDomain, atClientPreference.rootPort);
    final registrarService = RegistrarService(rootEnvironment);
  }

  Future<void> onboarding() async {
    final onboardRequest = AtOnboardingRequest(_onboardingAtSign!)
      ..rootDomain = _atClientPreference!.rootDomain
      ..rootPort = _atClientPreference!.rootPort;
    final onboardResult = await _atAuthService!.onboard(onboardRequest);
    if (onboardResult.isSuccessful) {
      // Onboarding successful
    } else {
      // Onboarding failed
    }
  }
}

enum LoginRequestResult {
  success,
  keysMissing,
  error,
}

enum AuthenticationStates {
  loading,
  authenticating,
  cuttingKeys,
  success,
  failure,
}

// TODO: Give the user the option to save the provided keys to the keychain
