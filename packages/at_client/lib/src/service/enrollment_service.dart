import 'package:at_auth/at_auth.dart';
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/util/enroll_list_request_param.dart';

/// [EnrollmentService] contains methods to fetch the enrollment details and methods to perform operations on the enrollments.
///
/// An app reaches these through `client.enrollments`, which builds each
/// decision from an enrollment id.
abstract class EnrollmentService {
  /// Fetches all enrollment requests from the server. Optionally accepts [EnrollmentListRequestParam] to filter the
  /// enrollment requests.
  ///
  /// ```dart
  /// final requests = await client.enrollmentService.fetchEnrollmentRequests();
  /// ```
  Future<List<Enrollment>> fetchEnrollmentRequests(
      {EnrollmentListRequestParam? enrollmentListParams});

  /// Approves the enrollment request [enrollmentRequestDecision] names.
  ///
  /// ```dart
  /// await client.enrollments.approve(enrollmentId); // builds the decision
  /// ```
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision);

  /// Denies an enrollment request. When an enrollment is denied, the requesting app is prevented from login into the application.
  ///
  /// ```dart
  /// await client.enrollments.deny(enrollmentId);
  /// ```
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision);

  /// Revokes an approved enrollment. When an enrollment ID is revoked, it becomes expired and cannot be used further.
  ///
  /// ```dart
  /// await client.enrollments.revoke(enrollmentId);
  /// ```
  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision);
}
