/// Process-wide network timeout policy for the Atsign SDK.
///
/// Every network operation that can block — connecting to an atServer or the
/// atDirectory, waiting for a response, and the retry loops around them — is
/// bounded by a deadline derived from [defaultTimeout], and no effective
/// timeout is ever allowed to exceed [maxAllowed].
///
/// This is the single place to change the default for the whole process: set
/// [defaultTimeout] once (e.g. at app start). Individual call sites may override
/// it (`AtClientPreference.networkTimeout`, `RetryOptions.overallTimeout`,
/// `SecureSocketConfig.connectTimeout`, or a per-call parameter), but every
/// resolved value is passed through [cap], so nothing can ever wait longer than
/// [maxAllowed].
class AtNetworkTimeouts {
  AtNetworkTimeouts._();

  /// The hard ceiling on any effective network timeout. Nothing waits longer
  /// than this, regardless of what a caller requests.
  static const Duration maxAllowed = Duration(seconds: 30);

  /// The process-wide default network timeout. Change this once to move the
  /// default everywhere. Always read through [cap] / [effectiveDefault] so it
  /// can never exceed [maxAllowed].
  static Duration defaultTimeout = const Duration(seconds: 30);

  /// Returns [d] clamped to the range `[Duration.zero, maxAllowed]`.
  static Duration cap(Duration d) {
    if (d > maxAllowed) return maxAllowed;
    if (d < Duration.zero) return Duration.zero;
    return d;
  }

  /// The [defaultTimeout], already capped at [maxAllowed].
  static Duration get effectiveDefault => cap(defaultTimeout);
}
