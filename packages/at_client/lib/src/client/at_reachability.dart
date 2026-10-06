/// Why `AtClient.ensureReachable` answered as it did.
///
/// An outcome, not a completion: a posture that does not seed, a namespace
/// that can never hold a key and a client with no key source are
/// configuration, so they are reported as values here rather than thrown.
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

  /// This client has no key source (`AtKeysIo`) to file a private half in, so
  /// it mints nothing: a key published with its private held only in memory
  /// is one peers seal to and nobody can open once the process ends.
  noKeySource,

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

  /// Whether this client holds the private half of every key the namespace
  /// offers peers to seal to, and so can open what a peer seals there now.
  ///
  /// Checked for both reachable outcomes and false for every other. False on a
  /// reachable namespace means peers can seal to it and this client cannot
  /// open what they seal: another enrollment published the key and its
  /// private has not reached this one. Also false when the check itself could
  /// not be made, which never changes [outcome].
  final bool holdsPrivate;

  const AtReachabilityResult(this.outcome,
      {this.error, this.holdsPrivate = false});

  /// Whether a peer can seal to this namespace now.
  ///
  /// True for both [AtReachability.alreadyReachable] and
  /// [AtReachability.published]; read this rather than comparing the outcome.
  bool get isReachable =>
      outcome == AtReachability.alreadyReachable ||
      outcome == AtReachability.published;

  @override
  String toString() => 'AtReachabilityResult(${outcome.name}'
      '${isReachable ? ', holdsPrivate: $holdsPrivate' : ''}'
      '${error == null ? '' : ', $error'})';
}
