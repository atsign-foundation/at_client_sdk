import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';

/// An abstract class for submitting and managing the enrollment requests.
abstract class AtEnrollmentService {
  /// Submits an enrollment request.
  ///
  /// The [atEnrollmentRequest] parameter represents the enrollment request details.
  ///
  /// Returns a [Future] containing an [EnrollResponse] representing the
  /// result of the enrollment.
  Future<AtEnrollmentResponse> submitEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest);

  /// Manages the approval/denial of an enrollment request.
  ///
  /// The [atEnrollmentRequest] parameter represents the enrollment request details.
  ///
  /// Returns a [Future] containing an [AtEnrollmentResponse] representing the
  /// result of the approval/denial of an enrollment.
  Future<AtEnrollmentResponse> manageEnrollmentApproval(
      AtEnrollmentRequest atEnrollmentRequest);

  /// Runs a scheduler which check if an enrollment is approved.
  ///
  /// Retrieves the [_EnrollmentInfo] from the key-chain manager. If
  /// If an enrollment is approved, then atKeys file is generated and removes the [_EnrollmentInfo] from
  /// the key-chain.
  ///
  /// Handles the scheduled enrollment authentication.
  ///
  /// - This method is invoked by a timer, attempting to authenticate an enrollment
  /// based on the [_EnrollmentInfo] stored in the key-chain manager
  ///
  /// - If there is no pending enrollment to retry authentication, the scheduler stops.
  /// - If the maximum retry count for enrollment authentication is reached,
  ///   the enrollment info is removed from the flutter key-chain, and the scheduler stops.
  /// - If authentication succeeds, then generated the atKeys file for authentication
  ///   and removes the enrollment info from the key-chain manager and stops the scheduler.
  /// - If authentication fails, the method retries with an incremented retry count.


  Future<EnrollmentStatus> getFinalEnrollmentStatus();
}
