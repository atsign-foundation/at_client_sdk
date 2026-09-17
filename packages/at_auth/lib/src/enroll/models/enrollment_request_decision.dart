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
  late final String _enrollmentId;
  late final String _atSign;
  late final String _encryptedAPKAMSymmetricKey;
  String? _mintedApkamSymmetricKey;
  late final EnrollOperationEnum _enrollOperationEnum;
  bool force = false;

  String get enrollmentId => _enrollmentId;

  String get atSign => _atSign;

  String get encryptedAPKAMSymmetricKey => _encryptedAPKAMSymmetricKey;

  /// The plaintext symmetric key this approver minted for an enrollment that
  /// advertised a key package, or null for the RSA path.
  ///
  /// When set, the approver generated the key rather than unwrapping one the
  /// enrollee sent, and delivers it by encapsulating it to the advertised
  /// public half — so [encryptedAPKAMSymmetricKey] is empty and there is
  /// nothing to RSA-decrypt.
  String? get mintedApkamSymmetricKey => _mintedApkamSymmetricKey;

  EnrollOperationEnum get enrollOperationEnum => _enrollOperationEnum;

  // Private constructor to prevent creating object.
  // Use static factory methods to get instance of EnrollmentRequestDecision
  EnrollmentRequestDecision._();

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
    required String enrollmentId,
    required AtBytes apkamSymmetricKey,
    required String atSign,
  }) {
    EnrollmentRequestDecision enrollmentRequestDecision =
        EnrollmentRequestDecision._()
          .._enrollmentId = enrollmentId
          .._atSign = atSign
          .._encryptedAPKAMSymmetricKey = apkamSymmetricKey.toString()
          .._enrollOperationEnum = EnrollOperationEnum.approve;

    return enrollmentRequestDecision;
  }

  /// Approves an enrollment that advertised a key package, with a symmetric
  /// key this approver minted.
  ///
  /// The enrollee sent none — its request carried no RSA-wrapped secret at all
  /// — so the key travels the other way, encapsulated to the public half the
  /// request advertised. The approver still wraps the encryption private key
  /// and the self-encryption key under it exactly as on the RSA path; only the
  /// key's origin and its route to the enrollee differ.
  static EnrollmentRequestDecision approvedWithMintedKey({
    required String enrollmentId,
    required String apkamSymmetricKey,
    required String atSign,
  }) {
    return EnrollmentRequestDecision._()
      .._enrollmentId = enrollmentId
      .._atSign = atSign
      .._encryptedAPKAMSymmetricKey = ''
      .._mintedApkamSymmetricKey = apkamSymmetricKey
      .._enrollOperationEnum = EnrollOperationEnum.approve;
  }

  /// If the request is denied, the requester application is prevented from authenticating to the atServer.
  ///
  /// ```dart
  ///  EnrollmentRequestDecision enrollmentRequestDecision = EnrollmentRequestDecision.denied('dummy-enrollment-id');
  /// ```
  static EnrollmentRequestDecision denied(String enrollmentId, String atSign) {
    return EnrollmentRequestDecision._()
      .._enrollmentId = enrollmentId
      .._atSign = atSign
      .._enrollOperationEnum = EnrollOperationEnum.deny;
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
  static EnrollmentRequestDecision revoked(String enrollmentId, String atSign,
      {bool force = false}) {
    return EnrollmentRequestDecision._()
      .._enrollmentId = enrollmentId
      .._atSign = atSign
      .._enrollOperationEnum = EnrollOperationEnum.revoke
      ..force = force;
  }
}
