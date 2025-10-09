import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';

/// The class holds details regarding an enrollment request, where the server notifies the approving app upon receiving a
/// request from the requesting app, seeking approval or denial.
///
/// The EnrollmentServerResponse includes the following fields:
///
///   - appName: The name of the app initiating the enrollment request.
///   - deviceName: The name of the device.
///   - namespace: This field determines the namespaces for granting access to view or write data based on permissions.
///   - encryptedAPKAMSymmetricKey: In the event of approval, the encryptedAPKAMSymmetricKey is used to encrypt the default
///                                 encryption private key and self-encryption key, facilitating the generation of the APKAM key pair.
class EnrollmentServerResponse {
  late String appName;
  late String deviceName;
  late Map<String, String> namespace;
  late String encryptedAPKAMSymmetricKey;
}

/// Represents the response of an enrollment operation received
/// from the secondary server.
class AtEnrollmentResponse {
  /// The unique identifier associated with the enrollment.
  String enrollmentId;

  /// The status of the enrollment operation.
  EnrollmentStatus enrollStatus;

  /// Optional atSign associated with the enrollment.
  String? atSign;
  /// Optional root domain associated with the enrollment.
  AtRootDomain? rootDomain;
  /// The authentication keys associated with the enrollment.
  AtKeys? atAuthKeys;

  /// Creates an instance of [AtEnrollmentResponse].
  ///
  /// The [enrollmentId] is the unique identifier for the enrollment.
  /// The [enrollStatus] represents the status of the enrollment operation.
  /// The [atAuthKeys] are  authentication keys associated with the enrollment.
  AtEnrollmentResponse(this.enrollmentId, this.enrollStatus,
      {this.atSign, this.rootDomain, this.atAuthKeys});

  @override
  String toString() {
    return 'AtEnrollmentResponse{enrollmentId: $enrollmentId, enrollStatus: $enrollStatus}';
  }
}
