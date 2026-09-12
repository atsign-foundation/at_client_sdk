import 'package:at_auth/at_auth.dart';
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/util/enroll_list_request_param.dart';

/// [EnrollmentService] contains methods to fetch the enrollment details and methods to perform operations on the enrollments.
abstract class EnrollmentService {
  /// Fetches all enrollment requests from the server. Optionally accepts [EnrollListRequestParams] to filter the enrollment
  /// requests. The enrollments are returned as `List<EnrollmentRequestDetails>`.
  ///
  /// ```dart
  /// Example:
  ///
  ///  final client = await Atsign('@alice').open(keys: keys, preference: preference);
  ///
  ///
  ///   List<EnrollmentRequest> enrollmentRequests = client.enrollmentService.fetchEnrollmentRequests();
  /// ```
  Future<List<Enrollment>> fetchEnrollmentRequests(
      {EnrollmentListRequestParam? enrollmentListParams});

  /// Approves the enrollment request.
  ///
  /// Example:
  ///
  /// ```dart
  ///     final client = await Atsign('@alice').open(keys: keys, preference: preference);
  ///
  ///     EnrollmentRequestDecision enrollmentRequestDecision =
  ///                              EnrollmentRequestDecision.approved(ApprovedRequestDecisionBuilder(
  ///                                            enrollmentId: 'dummy-enrollment-id',
  ///                                            encryptedAPKAMSymmetricKey: 'dummy-encrypted-apkam-symmetric-key'));
  ///
  /// AtEnrollmentResponse atEnrollmentResponse = await client.enrollmentService.approve(enrollmentRequestDecision);
  /// ```
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision);

  /// Denies an enrollment request. When an enrollment is denied, the requesting app is prevented from login into the application.
  ///
  /// Example:
  ///
  /// ```dart
  ///      final client = await Atsign('@alice').open(keys: keys, preference: preference);
  ///
  ///     EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.denied('dummy-enrollment-id');
  ///
  ///    AtEnrollmentResponse atEnrollmentResponse = await client.enrollmentService.deny(enrollmentRequestDecision);
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision);

  /// Revokes an approved enrollment. When an enrollment ID is revoked, it becomes expired and cannot be used further.
  ///
  /// Example:
  ///
  /// ```dart
  /// final client = await Atsign('@alice').open(keys: keys, preference: preference);
  ///
  ///     EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.revoked('dummy-enrollment-id');
  ///
  ///    AtEnrollmentResponse atEnrollmentResponse = await client.enrollmentService.revoke(enrollmentRequestDecision);
  /// ```
  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision);
}
