/// How an activation waits for a newly registered atSign to be provisioned.
class RetryOptions {
  static const int defaultMaxRetries = 10;
  static const Duration defaultRetryDelay = Duration(seconds: 2);
  static const defaultRetryOptions = RetryOptions(
      maxRetries: defaultMaxRetries, retryDelay: defaultRetryDelay);

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
