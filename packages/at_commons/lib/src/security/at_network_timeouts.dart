/// Process-wide network timeout policy for the Atsign SDK.
///
/// Every individual network operation that can block — connecting to an atServer
/// or the atDirectory, or waiting for a response — is bounded and capped at
/// [maxAllowed]. Retry/poll loops that repeat such operations (e.g. the
/// onboarding provisioning wait, [defaultOnboardingTimeout]) are bounded by their
/// own overall budget, which may be longer than [maxAllowed].
///
/// This is the single place to change the default for the whole process: set
/// [defaultTimeout] once (e.g. at app start). Individual call sites may override
/// it (`AtClientPreference.networkTimeout`, `RetryOptions.overallTimeout`,
/// `SecureSocketConfig.connectTimeout`, or a per-call parameter), but every
/// resolved value is passed through [cap], so nothing can ever wait longer than
/// [maxAllowed].
class AtNetworkTimeouts {
  AtNetworkTimeouts._();

  /// The hard ceiling on any single network operation (a connect, an atDirectory
  /// lookup, or a response wait). Nothing waits longer than this per operation,
  /// regardless of what a caller requests. Note this bounds *operations*, not
  /// retry/poll loops (see [defaultOnboardingTimeout]).
  static const Duration maxAllowed = Duration(seconds: 60);

  /// The process-wide default network timeout for a single reach-the-atServer
  /// attempt (the authentication path). Change this once to move the default
  /// everywhere. Always read through [cap] / [effectiveDefault] so it can never
  /// exceed [maxAllowed].
  static Duration defaultTimeout = const Duration(seconds: 30);

  /// The default overall budget for the ONBOARDING poll: how long to wait for a
  /// newly-registered atSign to be provisioned before giving up. Much longer than
  /// [defaultTimeout] because provisioning can take minutes, and NOT capped by
  /// [maxAllowed] — that cap is for individual operations, whereas this bounds a
  /// whole retry/poll loop. Settable to change the default.
  static Duration defaultOnboardingTimeout = const Duration(minutes: 5);

  /// Returns [d] clamped to the range `[Duration.zero, maxAllowed]`.
  static Duration cap(Duration d) {
    if (d > maxAllowed) return maxAllowed;
    if (d < Duration.zero) return Duration.zero;
    return d;
  }

  /// The [defaultTimeout], already capped at [maxAllowed].
  static Duration get effectiveDefault => cap(defaultTimeout);
}
