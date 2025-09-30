import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_utils/at_progress.dart';

class AuthService {
  final AtAuth _atAuth = AtAuth.create();
  Stream<ProgressEvent> get progressStream => _atAuth.progressStream;

  Future<AtOnboardingResponse> onboard(
      AtOnboardingRequest request, String cramSecret) async {
    AtOnboardingResponse? atOnboardingResponse;
    try {
      atOnboardingResponse = await _atAuth.onboard(request, cramSecret);
      // Save the atAuthKeys in keychain if it hasn't already.
      if (atOnboardingResponse.isSuccessful &&
          request.atKeysIo is! KeychainAtKeysIo) {
        var keychain = KeychainAtKeysIo();
        await keychain.write(request.atSign, atOnboardingResponse.atAuthKeys);
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
        var keychain = KeychainAtKeysIo();
        await keychain.write(atAuthRequest.atSign, atAuthResponse.atAuthKeys);
      }
    } catch (e) {
      rethrow;
    }
    return atAuthResponse;
  }
}
