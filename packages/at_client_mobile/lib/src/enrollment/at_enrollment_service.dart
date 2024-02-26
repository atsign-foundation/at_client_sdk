import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/at_client_mobile.dart';

/// An abstract class for submitting and managing the enrollment requests.
abstract class AtEnrollmentService {
  /// Submits an enrollment request. Only one enrollment request can be submitted at a time.
  /// Subsequent requests cannot be submitted until the pending enrollment request is fulfilled.
  ///
  /// The [atEnrollmentRequest] parameter represents the enrollment request details.
  ///
  /// Returns a [Future] representing EnrollmentId.
  ///
  /// Throws an [InvalidRequestException] if a new enrollment is submitted while there is already a pending enrollment.
  Future<String> submitEnrollmentRequest(
      AtEnrollmentRequest atEnrollmentRequest);

  /// Approves an enrollment request.
  Future<AtEnrollmentResponse> approve(AtEnrollmentRequest atEnrollmentRequest);

  /// Denies an enrollment request
  Future<AtEnrollmentResponse> deny(AtEnrollmentRequest atEnrollmentRequest);

  /// Provides the final enrollment status.
  ///
  /// [EnrollmentStatus.approved] signifies successful approval of the enrollment,
  /// allowing the user to utilize the enrollment ID for APKAM authentication.
  ///
  /// [EnrollmentStatus.denied] indicates that the enrollment ID is not eligible for
  /// APKAM authentication.
  Future<EnrollmentStatus> getFinalEnrollmentStatus();

  /// returns enrollment request data
  ///
  /// returns null if no enrollment request found
  Future<EnrollmentInfo?> getSentEnrollmentRequest();
}
