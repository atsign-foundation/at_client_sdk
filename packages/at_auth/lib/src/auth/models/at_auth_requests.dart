import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

sealed class AuthRequest {
  Atsign atsign;
  AtRootDomain rootDomain;
  AtKeysIo atKeysIo;
  String? namespace;

  AuthRequest(
    this.atsign,
    this.atKeysIo, {
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
    super.atSign,
    super.atKeysIo, {
    super.rootDomain,
    super.retryOptions,
  });

  // Default root domain and port
  String appName = "firstApp";
  String deviceName = "firstDevice";
}

class AtAuthRequest extends AuthRequest {
  /// Constructor for [AtAuthRequest]
  /// [atSign] is the atSign for authentication
  ///
  /// [atKeysIo] controls how AtKeys are loaded and saved (e.g. file system, keychain, secure element)
  ///
  /// optional:
  /// [rootDomain] is the default domain of the root server (e.g. root.atsign.org, 64)
  AtAuthRequest(
    super.atSign,
    super.atKeysIo, {
    super.rootDomain,
    super.retryOptions,
  });

  String? enrollmentId;
}

class RetryOptions {
  static const defaultRetryOptions =
      RetryOptions(retryDelay: Duration(milliseconds: 100));

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

  static Duration cap(Duration time, Duration cap) => time > cap ? cap : time;

  const RetryOptions({required this.retryDelay, this.overallTimeout});
}
