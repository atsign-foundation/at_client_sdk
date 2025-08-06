import 'package:at_auth/src/enroll/base_enrollment_request.dart';

/// The [EnrollmentRequest] is used by the apps to submit enrollment request for APKAM keys which provides .atKeys specific to
/// an application with restricted access to the namespaces. The application can access only the namespaces which are specified
/// in the enrollment request. If the namespace has Read-Write access then the application is allowed to create/update the data,
/// otherwise, if the namespace has only Read access then the application is allowed to read the data, but cannot create/update
/// the data.
///
/// This request is sent to the server and subsequently notified to apps with access to the "__manage" namespace. Upon approval, the requesting app is authenticated and granted
/// authorization to access the specified namespaces in the request. Conversely, if the request is disapproved, the requesting
/// app is denied login access.
class EnrollmentRequest extends BaseEnrollmentRequest {
  Map<String, String> namespaces;
  String? encryptedAPKAMSymmetricKey;
  String otp;
  Duration? apkamKeysExpiryDuration;

  EnrollmentRequest(
      {required super.appName,
      required super.deviceName,
      super.apkamPublicKey,
      required this.otp,
      required this.namespaces,
      this.encryptedAPKAMSymmetricKey,
      this.apkamKeysExpiryDuration});
}
