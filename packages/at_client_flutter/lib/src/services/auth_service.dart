import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
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
  ///   [timeout] - Overall wall-clock budget for the whole onboarding attempt,
  ///   including the poll that waits for a newly-registered atSign to be
  ///   provisioned. **Leave this null** to keep the default provisioning poll
  ///   (`AtNetworkTimeouts.defaultOnboardingTimeout`, 5 minutes) — a new atSign
  ///   can take minutes to provision, and a short value here truncates that
  ///   wait, so onboarding may time out before the atServer comes up. Pass a
  ///   value only to deliberately widen the window (e.g. an unusually slow
  ///   provisioner) or narrow it. It bounds the overall poll, not each probe:
  ///   individual network calls stay capped at 60s regardless.
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
  ///   [timeout] - Overall wall-clock budget for the authentication attempt.
  ///   Leave null to use the default (`AtNetworkTimeouts.effectiveDefault`,
  ///   30s), which fails fast when the atServer is unreachable. Unlike
  ///   [onboard], this path authenticates an *existing* atSign, so there is no
  ///   provisioning wait to accommodate — override only to tune the fail-fast
  ///   window.
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

  /// Builds a client from a completed authentication, which the caller owns.
  ///
  /// Nothing registers the client: it is unknown to [AtClientManager], and
  /// stopping it is the caller's job. An app that wants the shared
  /// current-atSign client calls [AtClientManager.fromAuthSession] instead,
  /// which is unchanged.
  ///
  ///   [session] - the [AtAuthSession] an [onboard] or [authenticate] produced.
  ///   Its root domain is destructured onto [preference].
  ///
  ///   [storage] - the client's local storage, which decides the backend and
  ///   the location and so leaves `preference.hiveStoragePath` unread.
  ///   Borrowed rather than owned: the client detaches from it when it stops,
  ///   and closing it is the caller's job. Leave it null and the client opens
  ///   a Hive store under `hiveStoragePath` and closes that itself.
  ///
  ///   [reuse] - adopt the session's already-authenticated connection and skip
  ///   a second PKAM handshake. By default the client opens its own.
  Future<AtClient> createClient(
    AtAuthSession session,
    AtClientPreference preference, {
    AtClientStorage? storage,
    bool reuse = false,
  }) async {
    preference.rootDomain = session.rootDomain.rootDomain;
    preference.rootPort = session.rootDomain.rootPort;
    return AtClient.create(
      atSign: session.atSign,
      namespace: session.namespace,
      preference: preference,
      atKeysIo: session.atKeysIo,
      atLookUp: reuse ? session.atLookUp : null,
      enrollmentId: session.enrollmentId,
      storage: storage,
    );
  }
}
