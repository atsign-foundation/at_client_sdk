import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_utils/at_progress.dart';

class AuthService {
  late final AtAuth _atAuth;
  late final KeychainAtKeysIo _keychainAtKeysIo;
  Stream<ProgressEvent> get progressStream => _atAuth.progressStream;

// DI to allow mocking in tests
  AuthService({AtAuth? atAuth, KeychainAtKeysIo? keychainAtKeysIo})
      : _atAuth = atAuth ?? AtAuth.create(),
        _keychainAtKeysIo = keychainAtKeysIo ?? KeychainAtKeysIo();

  Future<AtOnboardingResponse> onboard(
      AtOnboardingRequest request, String cramSecret) async {
    AtOnboardingResponse? atOnboardingResponse;
    try {
      atOnboardingResponse = await _atAuth.onboard(request, cramSecret);
      // Save the atAuthKeys in keychain if it hasn't already.
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

  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    AtAuthResponse? atAuthResponse;
    try {
      atAuthResponse = await _atAuth.authenticate(atAuthRequest);
      // Save the atAuthKeys in keychain if it hasn't already.
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
