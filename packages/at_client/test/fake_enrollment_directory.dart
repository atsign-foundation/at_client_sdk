import 'package:at_client/at_client_mixins.dart';

/// In-memory [EnrollmentDirectory] for tests.
///
/// Holds one key package per enrollment (1:1:1) and a namespace ->
/// {enrollmentId: access} map that models the atServer's namespace
/// authorization (only authorized enrollments are discoverable for a
/// namespace). One instance is shared across the test's sharers, so a key
/// package [seed]ed for one enrollment another can discover.
///
/// In production a key package reaches the enrollment record by riding
/// `enroll:request`; tests model that with [seed] — there is no registration
/// verb on the directory seam.
class FakeEnrollmentDirectory implements EnrollmentDirectory {
  /// enrollmentId -> its single key package (1:1:1).
  final Map<String, KeyPackage> registered = {};

  final Map<String, Map<String, String>> _nsAccess = {};

  /// Records [keyPackage] as [enrollmentId]'s single key package (1:1:1),
  /// modelling the package the enrollment carried on `enroll:request`.
  void seed(String enrollmentId, KeyPackage keyPackage) {
    registered[enrollmentId] = keyPackage;
  }

  @override
  Future<List<NamespaceMember>> listForNamespace(
    String namespace, {
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    final access = _nsAccess[namespace] ?? const {};
    final members = <NamespaceMember>[];
    access.forEach((enrollmentId, acc) {
      if (excludeEnrollmentIds.contains(enrollmentId)) return;
      final kp = registered[enrollmentId];
      members.add(NamespaceMember(
        enrollmentId: enrollmentId,
        access: acc,
        keyPackage: kp,
      ));
    });
    return members;
  }

  /// Authorizes [enrollmentId] for [namespace] (so it becomes discoverable
  /// there), modelling an atServer enrollment approval.
  void authorize(String namespace, String enrollmentId,
      {String access = 'rw'}) {
    _nsAccess.putIfAbsent(namespace, () => {})[enrollmentId] = access;
  }

  /// Drops [enrollmentId] from every namespace roster, modelling
  /// `enroll:revoke` — the atServer's `enroll:listns` returns **approved**
  /// enrollments only, so a revoked one stops appearing to anybody.
  void revoke(String enrollmentId) {
    for (final access in _nsAccess.values) {
      access.remove(enrollmentId);
    }
  }
}
