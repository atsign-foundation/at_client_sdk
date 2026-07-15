import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_utils/at_progress.dart';

class AuthService {
  late final AtAuth _atAuth;

  /// Stream of progress events during onboarding/authentication
  Stream<ProgressEvent> get progressStream => _atAuth.progressStream;

  // DI to allow mocking in tests
  AuthService({AtAuth? atAuth}) : _atAuth = atAuth ?? AtAuth.create();

  /// Onboarding an atSign for the first time
  ///
  ///   [request] - AtOnboardingRequest containing atSign, AtRootDomain and optional AtKeysIo
  ///
  ///   [cramSecret] - Cram secret
  ///
  /// Returns [AtOnboardingResponse] which contains keys and status of onboarding
  Future<AtOnboardingResponse> onboard(
    AtOnboardingRequest request,
    String cramSecret, {
    Duration? timeout,
  }) async {
    AtOnboardingResponse? atOnboardingResponse;
    try {
      request.atKeysIo ??= KeychainAtKeysIo();
      if (timeout != null) {
        request.retryOptions = RetryOptions(
          maxRetries: request.retryOptions.maxRetries,
          retryDelay: request.retryOptions.retryDelay,
          overallTimeout: timeout,
        );
      }
      atOnboardingResponse = await _atAuth.onboard(request, cramSecret);
    } catch (e) {
      rethrow;
    }
    return atOnboardingResponse;
  }

  /// Authenticate an atSign with secondary server
  ///
  ///   [atAuthRequest] - AtAuthRequest containing atSign, AtRootDomain, AtKeysIo.
  ///
  ///		[backupKeys] - Optional Parameter allowing for your keys to be backed up via provided WrittenAtKeysIo implementations
  ///
  /// Returns [AtAuthResponse] which contains keys and status of authentication
  Future<AtAuthResponse> authenticate(
    AtAuthRequest atAuthRequest, {
    List<WrittenAtKeysIo>? backupKeys,
    Duration? timeout,
  }) async {
    AtAuthResponse? atAuthResponse;
    try {
      if (timeout != null) {
        atAuthRequest.retryOptions = RetryOptions(
          maxRetries: atAuthRequest.retryOptions.maxRetries,
          retryDelay: atAuthRequest.retryOptions.retryDelay,
          overallTimeout: timeout,
        );
      }
      atAuthResponse = await _atAuth.authenticate(atAuthRequest);
      if (backupKeys != null &&
          atAuthResponse.atAuthKeys != null &&
          atAuthResponse.isSuccessful) {
        for (var atKeysIo in backupKeys) {
          atKeysIo.write(atAuthRequest.atSign, atAuthResponse.atAuthKeys!);
        }
      }
    } catch (e) {
      rethrow;
    }
    return atAuthResponse;
  }
}
