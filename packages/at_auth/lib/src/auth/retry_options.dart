/// Bounds `AtAuth.validateAtServer`'s reach-the-atServer loop, which retries
/// every [retryDelay] until [overallTimeout] is spent and then throws
/// `AtTimeoutException`. There is no retry *count*: the deadline is the only
/// bound.
///
/// **Leaving [overallTimeout] null does not mean "no deadline" — it means the
/// deadline depends on which operation is running:**
///
/// | Operation             | Default budget | Why                                                          |
/// |-----------------------|----------------|--------------------------------------------------------------|
/// | `AtAuth.authenticate` | 30s            | a dead network should fail fast                              |
/// | `AtAuth.onboard`      | 5 min          | a newly-registered atSign can take minutes to be provisioned |
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
