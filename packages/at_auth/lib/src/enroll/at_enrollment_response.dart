import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';

/// Represents the response of an enrollment operation received
/// from the secondary server.
class AtEnrollmentResponse {
  /// The unique identifier associated with the enrollment.
  String enrollmentId;

  /// The status of the enrollment operation.
  EnrollmentStatus enrollStatus;

  /// Optional authentication keys associated with the enrollment.
  AtAuthKeys? atAuthKeys;

  /// Creates an instance of [AtEnrollmentResponse].
  ///
  /// The [enrollmentId] is the unique identifier for the enrollment.
  /// The [enrollStatus] represents the status of the enrollment operation.
  /// The [atAuthKeys] are optional authentication keys associated with the enrollment.
  AtEnrollmentResponse(this.enrollmentId, this.enrollStatus);

  @override
  String toString() {
    return 'AtEnrollmentResponse{enrollmentId: $enrollmentId, enrollStatus: $enrollStatus}';
  }
}
