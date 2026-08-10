/// How the SDK learns whether a client's enrollment is fully privileged —
/// holding `rw` on both `*` and `__manage`.
///
/// One injected seam rather than each subsystem resolving privilege its own
/// way: the PQ startup's root-private request and unanchored-enrollment
/// sweep consult it, and the secret-sharing request gate is intended to
/// consume the same seam. Implementations answer from the enrollment
/// record — the server's word — never from anything the client asserts
/// about itself, so an enrollment cannot grant itself a privilege it was
/// never given.
abstract interface class EnrollmentPrivilegeResolver {
  /// Whether this client's enrollment holds `rw` on both `*` and
  /// `__manage`. May cost a round trip; callers treat it as such.
  Future<bool> isFullyPrivileged();
}
