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
  /// The app this atSign is being onboarded from; recorded on the first
  /// enrollment so later enrollments can be attributed.
  final String appName;

  /// The device this atSign is being onboarded on.
  final String deviceName;

  /// Constructor for [AtOnboardingRequest]
  ///
  /// [atsign] is the atSign to onboard, and [atKeysIo] is where its freshly
  /// minted keys are persisted (e.g. file system, keychain, secure element).
  ///
  /// optional:
  /// [rootDomain] is the domain and port of the atDirectory
  ///   (default: root.atsign.org, 64)
  /// [appName]/[deviceName] name the first enrollment
  /// [retryOptions] bounds atServer reachability checks — see [RetryOptions],
  ///   which defaults to a 5 minute budget for onboarding
  AtOnboardingRequest(
    super.atsign,
    super.atKeysIo, {
    super.rootDomain,
    super.retryOptions,
    this.appName = 'firstApp',
    this.deviceName = 'firstDevice',
  });
}

class AtAuthRequest extends AuthRequest {
  /// Constructor for [AtAuthRequest]
  ///
  /// [atsign] is the atSign to authenticate, and [atKeysIo] is where its keys
  /// are read from (e.g. file system, keychain, secure element).
  ///
  /// optional:
  /// [rootDomain] is the domain and port of the atDirectory
  ///   (default: root.atsign.org, 64)
  /// [retryOptions] bounds atServer reachability checks — see [RetryOptions],
  ///   which defaults to a 30 second budget for authentication
  AtAuthRequest(
    super.atsign,
    super.atKeysIo, {
    super.rootDomain,
    super.retryOptions,
  });

  /// The enrollment to authenticate as. When null, `AtAuth.authenticate` falls
  /// back to the enrollmentId stored in the keys it reads.
  String? enrollmentId;
}

/// Bounds `AtAuth.validateAtServer`'s reach-the-atServer loop, which retries
/// every [retryDelay] until [overallTimeout] is spent and then throws
/// `AtTimeoutException`. There is no retry *count*: the deadline is the only
/// bound.
///
/// **Leaving [overallTimeout] null does not mean "no deadline" — it means the
/// deadline depends on which request this is attached to:**
///
/// | Request                | Default budget | Why |
/// |------------------------|----------------|-----|
/// | [AtAuthRequest]        | 30s            | a dead network should fail fast |
/// | [AtOnboardingRequest]  | 5 min          | a newly-registered atSign can take minutes to be provisioned |
///
/// (30s is `AtNetworkTimeouts.effectiveDefault`; 5 min is
/// `AtNetworkTimeouts.defaultOnboardingTimeout`.) Set [overallTimeout]
/// explicitly to override either.
class RetryOptions {
  static const defaultRetryOptions =
      RetryOptions(retryDelay: Duration(milliseconds: 100));

  /// How long to wait between attempts.
  final Duration retryDelay;

  /// The total wall-clock budget for reaching the atServer. See the class doc
  /// for what null means — it is request-dependent, not unbounded.
  ///
  /// Deliberately NOT clamped to `AtNetworkTimeouts.maxAllowed`: that cap
  /// applies to individual network operations, not to this overall loop.
  final Duration? overallTimeout;

  static Duration cap(Duration time, Duration cap) => time > cap ? cap : time;

  const RetryOptions({required this.retryDelay, this.overallTimeout});
}
