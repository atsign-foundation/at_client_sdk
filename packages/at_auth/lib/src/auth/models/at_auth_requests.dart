import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

sealed class AuthRequest {
  String atSign;
  AtRootDomain rootDomain;
  String? namespace;

  AuthRequest(
    this.atSign, {
    this.retryOptions = RetryOptions.defaultRetryOptions,
    this.rootDomain = AtRootDomain.atsignDomain,
    this.namespace,
  });

  /// Options for retrying operations that validate atServer status' for Onboarding.
  RetryOptions retryOptions;

  /// Signing algorithm to use for pkam authentication
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// Hashing algorithm to use for pkam authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;
}

class AtOnboardingRequest extends AuthRequest {
  /// Constructor for [AtOnboardingRequest]
  /// [atSign] is the atSign for onboarding
  ///
  /// optional:
  /// [rootDomain] is the default domain of the root server (e.g. root.atsign.org, 64)
  /// [appName] is the name of the app
  /// [deviceName] is the name of the device
  /// [atKeysIo] controls how AtKeys are loaded and saved (e.g. file system, keychain, secure element)

  AtOnboardingRequest(
    super.atSign, {
    this.atKeysIo,
    super.rootDomain,
    super.retryOptions,
  });

  // Default appName and deviceName
  String appName = "firstApp";
  String deviceName = "firstDevice";

  // Controls how the authentication is performed
  AtKeysIo? atKeysIo;
}

class AtAuthRequest extends AuthRequest {
  /// Constructor for [AtAuthRequest]
  /// [atSign] is the atSign for authentication
  ///
  /// [atKeysIo] controls how legacy fixed-field AtKeys are loaded and saved
  /// (e.g. file system, keychain, secure element)
  ///
  /// optional:
  /// [rootDomain] is the default domain of the root server (e.g. root.atsign.org, 64)
  AtAuthRequest(
    super.atSign,
    this.atKeysIo, {
    super.rootDomain,
    super.retryOptions,
  });

  // Controls how the authentication is performed
  AtKeysIo atKeysIo;
}

class RetryOptions {
  static const defaultRetryOptions =
      RetryOptions(maxRetries: 10, retryDelay: Duration(seconds: 2));

  final int maxRetries;
  final Duration retryDelay;

  const RetryOptions({required this.maxRetries, required this.retryDelay});
}
