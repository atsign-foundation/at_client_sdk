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

/// Whether [namespaces] grant `rw` on both `*` and `__manage` — the class
/// that may hold the signing root ([decisions.md 18.2][]).
///
/// Read off the granted namespaces rather than trusted from the caller: this
/// decides who receives the key that vouches for every enrollment on the
/// atSign.
///
/// [decisions.md 18.2]: ../../../../../docs/projects/pq/decisions.md
bool isFullyPrivileged(Map<String, dynamic>? namespaces) {
  if (namespaces == null) return false;
  bool grantsWrite(String ns) => '${namespaces[ns] ?? ''}'.contains('w');
  return grantsWrite('*') && grantsWrite('__manage');
}
