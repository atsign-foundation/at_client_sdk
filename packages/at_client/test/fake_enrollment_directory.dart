import 'package:at_client/at_client_mixins.dart';

/// In-memory [EnrollmentDirectory] for tests.
///
/// Holds registered key packages by enrollmentId, and a namespace ->
/// {enrollmentId: access} map that models the atServer's namespace
/// authorization (only authorized enrollments are discoverable for a
/// namespace). One instance is shared across the test's sharers, so a key
/// package one registers another can discover.
class FakeEnrollmentDirectory implements EnrollmentDirectory {
  /// enrollmentId -> its registered key packages (one per APKAM keypair).
  final Map<String, List<KeyPackage>> registered = {};

  final Map<String, Map<String, String>> _nsAccess = {};

  @override
  Future<void> registerKeyPackage(KeyPackage keyPackage) async {
    final list = registered.putIfAbsent(keyPackage.enrollmentId, () => []);
    list.removeWhere((e) => e.kpid == keyPackage.kpid);
    list.add(keyPackage);
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
      members.add(NamespaceMember(
        enrollmentId: enrollmentId,
        access: acc,
        keyPackages: List.of(registered[enrollmentId] ?? const []),
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
}
