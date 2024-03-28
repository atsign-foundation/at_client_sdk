import 'package:at_auth/at_auth.dart';
import 'package:at_client/src/response/pending_enrollment_request.dart';
import 'package:at_client/src/util/enroll_list_request_param.dart';
import 'package:at_commons/at_builders.dart';

/// [EnrollmentService] contains methods to fetch the enrollment details and methods to perform operations on the enrollments.
abstract class EnrollmentService {
  /// Fetches all enrollment requests from the server. Optionally accepts [EnrollListRequestParams] to filter the enrollment
  /// requests. The enrollments are returned as List<EnrollmentRequestDetails>.
  ///
  /// ```dart
  /// Example:
  ///
  ///  AtClientManager atClientManager = await AtClientManager.getInstance()
  ///                               .setCurrentAtSign('@alice', 'me', AtClientPreferences());
  ///
  ///
  ///   List<EnrollmentRequest> enrollmentRequests = atClientManager.atClient.encryptionService
  ///                                                     .fetchEnrollmentRequests();
  /// ```
  Future<List<PendingEnrollmentRequest>> fetchEnrollmentRequests(
      {EnrollListRequestParam? enrollmentListRequest});

  /// Approves the enrollment request.
  ///
  /// Example:
  ///
  /// ```dart
  ///     AtClientManager atClientManager = await AtClientManager.getInstance()
  ///                               .setCurrentAtSign('@alice', 'me', AtClientPreferences());
  ///
  ///     EnrollmentRequestDecision enrollmentRequestDecision =
  ///                              EnrollmentRequestDecision.approved(ApprovedRequestDecisionBuilder(
  ///                                            enrollmentId: 'dummy-enrollment-id',
  ///                                            encryptedAPKAMSymmetricKey: 'dummy-encrypted-apkam-symmetric-key'));
  ///
  /// AtEnrollmentResponse atEnrollmentResponse = await atClientManager.atClient
  ///                                                                  .enrollmentService.approve(enrollmentRequestDecision);
  /// ```
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision);

  /// Denies an enrollment request. When an enrollment is denied, the requesting app is
  ///
  /// Example:
  ///
  /// ```dart
  ///      AtClientManager atClientManager = await AtClientManager.getInstance()
  ///                              .setCurrentAtSign('@alice', 'me', AtClientPreferences());
  ///
  ///     EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.denied('dummy-enrollment-id');
  ///
  ///    AtEnrollmentResponse atEnrollmentResponse = await atClientManager.atClient
  ///                                                      .encryptionService.deny(enrollmentRequestDecision);
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision);

  Future<bool> isAuthorized(String key, VerbBuilder verbBuilder);
}
