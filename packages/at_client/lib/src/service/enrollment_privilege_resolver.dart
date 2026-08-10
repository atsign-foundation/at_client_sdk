import 'package:at_auth/at_auth.dart' show AtEnrollment;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;

/// The production [EnrollmentPrivilegeResolver]: reads the enrollment
/// record off the atServer.
///
/// Read off the enrollment record rather than anything this client asserts
/// about itself, so an enrollment cannot anchor itself to the signing root
/// by claiming a privilege it was never granted.
///
/// Costs a round trip, which is why callers only consult it once they hold
/// something that makes the answer matter — almost no client reaches it.
///
/// A client with no enrollment id is authenticating with the atSign's own
/// keys, which is full privilege by construction rather than by grant.
class EnrollmentRecordPrivilegeResolver implements EnrollmentPrivilegeResolver {
  EnrollmentRecordPrivilegeResolver(this._atClient);

  final AtClient _atClient;

  @override
  Future<bool> isFullyPrivileged() async {
    final id = _atClient.getRemoteSecondary()?.atLookUp.enrollmentId;
    if (id == null) return true;
    return isEnrollmentFullyPrivileged(id);
  }

  @override
  Future<bool> isEnrollmentFullyPrivileged(String enrollmentId) async {
    final theirs = (await EnrollmentServiceImpl(_atClient, AtEnrollment.create())
            .fetchEnrollmentRequests())
        .where((e) => e.enrollmentId == enrollmentId)
        .firstOrNull;
    return EnrollmentServiceImpl.isFullyPrivileged(theirs?.namespace);
  }
}
