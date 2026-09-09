import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart' as privilege;
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/util/enroll_list_request_param.dart';
import 'package:at_commons/at_commons.dart' show EnrollmentStatus;

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
  EnrollmentRecordPrivilegeResolver(this._atClient,
      {required Future<List<Enrollment>> Function(
              {EnrollmentListRequestParam? enrollmentListParams})
          listEnrollments})
      : _listEnrollments = listEnrollments;

  final AtClient _atClient;

  /// How the roster is fetched — injected so this resolver stays independent
  /// of the verb wrapper that owns `enroll:list`.
  final Future<List<Enrollment>> Function(
      {EnrollmentListRequestParam? enrollmentListParams}) _listEnrollments;

  @override
  Future<bool> isFullyPrivileged() async {
    final id = _atClient.getRemoteSecondary()?.atLookUp.enrollmentId;
    if (id == null || isAtSignCredential(id)) return true;
    return isEnrollmentFullyPrivileged(id);
  }

  /// Narrowed to `approved` because privilege is a property of an
  /// enrollment that currently holds it: a revoked or denied record
  /// answering here would grant authority the atServer no longer honours.
  /// An unfiltered `enroll:list` would also return every enrollment the
  /// atSign has ever held.
  @override
  Future<bool> isEnrollmentFullyPrivileged(String enrollmentId) async {
    final theirs = (await _listEnrollments(
            enrollmentListParams: EnrollmentListRequestParam()
              ..enrollmentListFilter = const [EnrollmentStatus.approved]))
        .where((e) => e.enrollmentId == enrollmentId)
        .firstOrNull;
    return privilege.isFullyPrivileged(theirs?.namespace);
  }
}
