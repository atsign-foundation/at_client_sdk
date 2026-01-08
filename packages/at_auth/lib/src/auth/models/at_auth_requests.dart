import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

sealed class AuthRequest {
  String atSign;
  AtRootDomain rootDomain;
  String? namespace;

  bool useLocal;

  AuthRequest(
    this.atSign, {
    this.retryOptions = RetryOptions.defaultRetryOptions,
    this.rootDomain = AtRootDomain.atsignDomain,
    this.useLocal = false,
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
  /// [atKeys] are the keys for authentication of an atSign

  AtOnboardingRequest(
    super.atSign, {
    super.rootDomain,
    super.useLocal,
    super.namespace,
    this.atKeysIo,
    this.atKeys,
  });

  // Default root domain and port
  String appName = "firstApp";
  String deviceName = "firstDevice";
  AtKeysIo? atKeysIo;
  AtKeys? atKeys;
}

class AtAuthRequest extends AuthRequest {
  /// Constructor for [AtAuthRequest]
  /// [atSign] is the atSign for authentication
  ///
  /// Must provide one of the following!
  /// atKeysIo - method of authentication
  ///    or
  /// atAuthKeys - the actual keys themselves
  ///
  /// [atKeysIo] controls how AtKeys are loaded and saved (e.g. file system, keychain, secure element)
  /// [atAuthKeys] are the keys for authentication of an atSign
  ///
  /// optional:
  /// [rootDomain] is the default domain of the root server (e.g. root.atsign.org, 64)
  AtAuthRequest(
    super.atSign, {
    super.namespace,
    super.rootDomain,
    super.useLocal,
    super.retryOptions,
    this.atKeysIo,
    this.atAuthKeys,
  }) {
    if (atKeysIo == null && atAuthKeys == null) {
      throw Exception(
          "Either method of authentication(atKeysIo) or atAuthKeys need to be provided");
    }
  }

  // Controls how the authentication is performed
  AtKeysIo? atKeysIo;

  /// The enrollmentId for APKAM authentication
  String? enrollmentId;

  /// The keys for authentication of an atSign.
  AtKeys? atAuthKeys;

  /// The contents of .atKeys file which contains the encrypted atKeys.
  Map<String, dynamic>? encryptedKeysMap;
}

class RetryOptions {
  static const defaultRetryOptions =
      RetryOptions(maxRetries: 10, retryDelay: Duration(seconds: 2));

  final int maxRetries;
  final Duration retryDelay;

  const RetryOptions({required this.maxRetries, required this.retryDelay});
}
