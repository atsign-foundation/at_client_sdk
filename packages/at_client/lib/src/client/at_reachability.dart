/// Why `AtClient.ensureReachable` answered as it did.
///
/// An **outcome**, not a completion. The distinction is the whole reason this
/// type exists: `PqClientBootstrap.startupComplete` resolves identically
/// whether the startup did its work or was stopped before doing any of it, so
/// an application cannot branch on it — and the one thing an application
/// actually wants to know is whether other atSigns can send to it yet.
///
/// Reported by a value rather than by throwing, because "this posture does not
/// seed" and "this enrollment is not authorised for that namespace" are
/// ordinary answers about how the client was configured, not failures.
enum AtReachability {
  /// A key was already published for the namespace; this call did nothing.
  alreadyReachable,

  /// This call minted and published the key, and conveyed its private half to
  /// the atSign's other enrollments.
  published,

  /// This client's `PqPosture` does not seed namespace keys, so nothing here
  /// or in its startup will publish one. Returned promptly rather than after
  /// the timeout: an app that chose `legacy` is not waiting for something that
  /// is coming.
  postureDoesNotSeed,

  /// The namespace named can never hold a key of its own, so nothing here or
  /// in any client's startup will publish one for it.
  ///
  /// `*` and `__manage` are grants over other namespaces rather than
  /// namespaces data lives in. A wildcard-only enrollment — which is what a
  /// first CRAM onboard produces — is therefore authorised for nothing
  /// seedable, and asking again later cannot change the answer. Decided from
  /// the namespace alone, with no round trip.
  ///
  /// **Not** "this enrollment was not granted that namespace". Establishing
  /// that costs a round trip to the enrollment record, and the atServer
  /// answers it anyway by refusing the write under the verb's own name — so an
  /// ungranted namespace arrives as [failed] carrying that refusal, which says
  /// which write was refused.
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
  /// [AtReachability.published] — a caller that only wants to know whether it
  /// can receive should read this and not compare the outcome, so that a
  /// future outcome meaning "reachable, by some other route" does not silently
  /// read as false.
  bool get isReachable =>
      outcome == AtReachability.alreadyReachable ||
      outcome == AtReachability.published;

  @override
  String toString() =>
      'AtReachabilityResult(${outcome.name}${error == null ? '' : ', $error'})';
}
