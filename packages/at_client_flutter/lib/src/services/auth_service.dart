import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_utils/at_progress.dart';

class AuthService {
  late final AtAuth _atAuth;
  late final KeychainAtKeysIo _keychainAtKeysIo;

  /// Stream of progress events during onboarding/authentication
  Stream<ProgressEvent> get progressStream => _atAuth.progressStream;

// DI to allow mocking in tests
  AuthService({AtAuth? atAuth, KeychainAtKeysIo? keychainAtKeysIo})
      : _atAuth = atAuth ?? AtAuth.create(),
        _keychainAtKeysIo = keychainAtKeysIo ?? KeychainAtKeysIo();

  /// Onboarding an atSign for the first time
  ///
  ///   [request] - AtOnboardingRequest containing atSign, AtRootDomain and optional AtKeysIo
  ///
  ///   [cramSecret] - Cram secret
  ///
  /// Returns [AtOnboardingResponse] which contains keys and status of onboarding
  Future<AtOnboardingResponse> onboard(
      AtOnboardingRequest request, String cramSecret) async {
    AtOnboardingResponse? atOnboardingResponse;
    try {
      atOnboardingResponse = await _atAuth.onboard(request, cramSecret);
      // Save the atAuthKeys in keychain if we didn't onboard via keychain.
      if (atOnboardingResponse.isSuccessful &&
          request.atKeysIo is! KeychainAtKeysIo) {
        await _keychainAtKeysIo.write(
            request.atSign, atOnboardingResponse.atAuthKeys);
      }
    } catch (e) {
      rethrow;
    }
    return atOnboardingResponse;
  }

  /// Authenticate an atSign with secondary server
  ///
  ///   [atAuthRequest] - AtAuthRequest containing atSign, AtRootDomain, AtKeysIo.
  /// Returns [AtAuthResponse] which contains keys and status of authentication
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    AtAuthResponse? atAuthResponse;
    try {
      atAuthResponse = await _atAuth.authenticate(atAuthRequest);
      // Save the atAuthKeys in keychain if we didn't auth via keychain.
      //If we authenticated via keychain, the keys have already been saved by atAuth.authenticate.
      if (atAuthResponse.isSuccessful &&
          atAuthRequest.atKeysIo is! KeychainAtKeysIo) {
        await _keychainAtKeysIo.write(
            atAuthRequest.atSign, atAuthResponse.atAuthKeys);
      }
    } catch (e) {
      rethrow;
    }
    return atAuthResponse;
  }
}
