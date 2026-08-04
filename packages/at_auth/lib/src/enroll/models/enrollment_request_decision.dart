import 'dart:core';

import 'package:at_commons/at_commons.dart';

/// This class serves as the entity responsible for either approving or denying an enrollment request.
/// The enrollment request is received through a notification from the server. The approving app has
/// the authority to either grant or deny the request, with approval resulting in authentication and
/// authorization to the requested namespaces.
///
/// To approve the request, the "enrollmentId" and its corresponding "encryptedAPKAMSymmetricKey,"
/// received through the notification, must be provided using the "AuthenticationRequestDecisionBuilder."
///
/// Upon approval, the encryptedAPKAMSymmetricKey undergoes decryption using the default encryption public key to
/// retrieve the original APKAM Symmetric key. Subsequently, the default encryption key pair and the self-encryption
/// key are encrypted with the APKAM symmetric key and transmitted to the server for the requesting app. The requesting
/// app, then decrypts the encrypted default encryption private key and self encryption key. These keys are used for
/// decryption of shared data and self data respectively..
///
/// ```dart
///  To approve an enrollment request
///
/// EnrollmentRequestDecision enrollmentRequestDecision =
///           EnrollmentRequestDecision.approved(ApprovedRequestDecisionBuilder(
///               enrollmentId: 'dummy-enrollment-id',
///               encryptedAPKAMSymmetricKey: 'dummy-encrypted-apkam-symmetric-key'));
/// ```
///
/// If the request is denied, the requester is prevented from logging into the application.
///
/// To deny an enrollment request
///
/// ```dart
///  EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.denied('dummy-enrollment-id');
/// ```
///
/// To revoke an enrollment request. Optionally, set "force" parameter to true to revoke the enrollment permission of the current client
/// which defaults to false.
///
/// Example:
/// ```dart
/// EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.revoked('enrollment123', force: false);
/// ```
class EnrollmentRequestDecision {
  final String enrollmentId;
  final Atsign atsign;
  final AtBytes? encryptedAPKAMSymmetricKey;
  final EnrollOperationEnum enrollOperationEnum;
  bool force = false;

  // Private constructor to prevent creating object.
  // Use static factory methods to get instance of EnrollmentRequestDecision
  EnrollmentRequestDecision._(
    this.atsign,
    this.enrollmentId,
    this.enrollOperationEnum, {
    this.encryptedAPKAMSymmetricKey,
  });

  /// To approve the request, the "enrollmentId" and its corresponding "encryptedAPKAMSymmetricKey,"
  /// received through the notification, must be provided using the "AuthenticationRequestDecisionBuilder."
  ///
  /// Upon approval, the encryptedAPKAMSymmetricKey undergoes decryption using the default encryption private key to
  /// retrieve the original APKAM Symmetric key. Subsequently, default encryption private key and self-encryption key
  /// are encrypted with the APKAM symmetric key and transmitted to server for the requesting app. The requesting app,
  /// then decrypts the encrypted default encryption private key and self encryption key. These keys are used for
  /// decryption of shared data and self data respectively..
  ///
  /// ```dart
  ///  To approve an enrollment request
  ///
  /// EnrollmentRequestDecision enrollmentRequestDecision =
  ///           EnrollmentRequestDecision.approved(ApprovedRequestDecisionBuilder(
  ///               enrollmentId: 'dummy-enrollment-id',
  ///               encryptedAPKAMSymmetricKey: 'dummy-encrypted-apkam-symmetric-key'));
  static EnrollmentRequestDecision approved({
    required Atsign atsign,
    required String enrollmentId,
    required AtBytes apkamSymmetricKey,
  }) {
    return EnrollmentRequestDecision._(
      atsign,
      enrollmentId,
      EnrollOperationEnum.approve,
      encryptedAPKAMSymmetricKey: apkamSymmetricKey,
    );
  }

  /// If the request is denied, the requester application is prevented from authenticating to the atServer.
  ///
  /// ```dart
  ///  EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.denied('dummy-enrollment-id');
  /// ```
  static EnrollmentRequestDecision denied(String enrollmentId, Atsign atsign) {
    return EnrollmentRequestDecision._(
      atsign,
      enrollmentId,
      EnrollOperationEnum.deny,
    );
  }

  /// Revokes an approved enrollment, closing any active connections and making it inactive for future use.
  ///
  /// Creates an [EnrollmentRequestDecision] to revoke an enrollment. This method generates an [EnrollmentRequestDecision]
  /// instance configured to revoke the enrollment specified by the provided [enrollmentId].
  /// By default, the current client cannot revoke its own enrollment permission. To allow the current client to revoke
  /// its own enrollment, set the force parameter to true.
  ///
  /// Example:
  /// ```dart
  /// EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.revoked('enrollment123', force: false);
  /// ```
  static EnrollmentRequestDecision revoked(String enrollmentId, Atsign atsign,
      {bool force = false}) {
    return EnrollmentRequestDecision._(
      atsign,
      enrollmentId,
      EnrollOperationEnum.revoke,
    )..force = force;
  }
}
