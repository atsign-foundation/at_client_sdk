/// Why `AtClient.ensureReachable` answered as it did.
///
/// An outcome, not a completion: a posture that does not seed and a namespace
/// that can never hold a key are configuration, so they are reported as values
/// here rather than thrown.
enum AtReachability {
  /// A key was already published for the namespace; this call did nothing.
  alreadyReachable,

  /// This call minted and published the key, and conveyed its private half to
  /// the atSign's other enrollments.
  published,

  /// This client's `PqPosture` does not seed namespace keys, so nothing here
  /// or in its startup will publish one. Returned promptly rather than after
  /// the timeout.
  postureDoesNotSeed,

  /// The namespace named can never hold a key of its own, so nothing here or
  /// in any client's startup will publish one for it.
  ///
  /// `*` and `__manage` are grants over other namespaces rather than
  /// namespaces data lives in, so a wildcard-only enrollment is authorised for
  /// nothing seedable. Decided from the namespace alone, with no round trip.
  ///
  /// Not "this enrollment was not granted that namespace": that arrives as
  /// [failed], carrying the atServer's refusal of the write.
  notAuthorised,

  /// The work did not finish inside the timeout. Nothing is known about
  /// whether it eventually will: a mint that was in flight may still land.
  timedOut,

  /// It failed. `AtReachabilityResult.error` carries what threw.
  failed,
}

/// What `AtClient.ensureReachable` answered, and why.
class AtReachabilityResult {
  final AtReachability outcome;

  /// What threw, for [AtReachability.failed]; null otherwise.
  final Object? error;

  const AtReachabilityResult(this.outcome, {this.error});

  /// Whether a peer can seal to this namespace now.
  ///
  /// True for both [AtReachability.alreadyReachable] and
  /// [AtReachability.published]; read this rather than comparing the outcome.
  bool get isReachable =>
      outcome == AtReachability.alreadyReachable ||
      outcome == AtReachability.published;

  @override
  String toString() =>
      'AtReachabilityResult(${outcome.name}${error == null ? '' : ', $error'})';
}
