import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
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
  /// [atKeys] are the keys for authentication of an atSign

  AtOnboardingRequest(
    super.atSign, {
    super.rootDomain,
    super.retryOptions,
    this.atKeysIo,
    this.atKeys,
  });

  // Default root domain and port
  String appName = "firstApp";
  String deviceName = "firstDevice";
  AtKeysIo? atKeysIo;
  @Deprecated('remove in v4')
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
    super.rootDomain,
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
  @Deprecated('remove in v4')
  AtKeys? atAuthKeys;

  /// The contents of .atKeys file which contains the encrypted atKeys.
  @Deprecated('remove in v4')
  Map<String, dynamic>? encryptedKeysMap;
}

class RetryOptions {
  static const defaultRetryOptions =
      RetryOptions(maxRetries: 10, retryDelay: Duration(seconds: 2));

  final int maxRetries;
  final Duration retryDelay;

  /// The maximum total wall-clock to spend reaching/validating the atServer —
  /// the whole retry/poll loop. When null, the default depends on the request:
  /// authentication uses the short process-wide default
  /// (`AtNetworkTimeouts.effectiveDefault`, 30s) so a dead network fails fast,
  /// while ONBOARDING uses `AtNetworkTimeouts.defaultOnboardingTimeout` (5 min)
  /// because a newly-registered atSign can take minutes to be provisioned. This
  /// bounds the loop and is deliberately NOT clamped to
  /// `AtNetworkTimeouts.maxAllowed` — that cap applies to individual network
  /// operations. Note [maxRetries] no longer bounds this loop; this deadline
  /// does (the loop retries every [retryDelay] until the budget is spent).
  final Duration? overallTimeout;

  const RetryOptions(
      {required this.maxRetries,
      required this.retryDelay,
      this.overallTimeout});
}
