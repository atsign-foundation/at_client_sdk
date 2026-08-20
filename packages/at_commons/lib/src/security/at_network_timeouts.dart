/// Process-wide network timeout policy for the Atsign SDK.
///
/// Every individual network operation that can block — connecting to an atServer
/// or the atDirectory, or waiting for the next bytes of a response — is bounded
/// and capped at [maxAllowed]. Budgets that bound an *aggregate* of such
/// operations are exempt from that cap and bounded by their own overall value:
/// the onboarding provisioning poll ([defaultOnboardingTimeout]) repeats an
/// operation until it succeeds, and a response budget ([defaultResponseBudget])
/// spans however many socket chunks one response arrives in.
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
  /// aggregates of them (see [defaultOnboardingTimeout], [defaultResponseBudget]).
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

  /// The default overall budget for ONE complete response from an atServer,
  /// measured from sending the command to the terminating byte arriving.
  ///
  /// Distinct from [defaultTimeout], which bounds the wait for the *next* bytes
  /// and restarts every time a chunk arrives. A large response — a stream, a
  /// long scan — is many such waits in a row, and only this budget bounds their
  /// sum, so a peer that trickles bytes indefinitely is caught by this and by
  /// nothing else.
  ///
  /// NOT capped by [maxAllowed], by design and necessarily: it bounds an
  /// aggregate rather than one operation, its own default already exceeds the
  /// 60s ceiling, and `at_client` passes `AtClientPreference`'s
  /// `outboundConnectionTimeout` — 600000 ms — as the budget for a stream read.
  /// Capping it would truncate both.
  ///
  /// 90 seconds preserves the long-standing default of
  /// `OutboundMessageListener.read`'s `maxWaitMilliSeconds`, so adopting this
  /// changes no behaviour. Settable to change the default.
  static Duration defaultResponseBudget = const Duration(seconds: 90);

  /// Returns [d] clamped to the range `[Duration.zero, maxAllowed]`.
  static Duration cap(Duration d) {
    if (d > maxAllowed) return maxAllowed;
    if (d < Duration.zero) return Duration.zero;
    return d;
  }

  /// The [defaultTimeout], already capped at [maxAllowed].
  static Duration get effectiveDefault => cap(defaultTimeout);
}
