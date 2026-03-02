import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/enroll/models/namespace_permission.dart';

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
  String enrollmentId;
  String appName;
  String deviceName;
  EnrollmentStatus status;
  List<NamespacePermission> namespace;
  String? encryptedAPKAMSymmetricKey;

  EnrollmentServerResponse({
    required this.enrollmentId,
    required this.appName,
    required this.deviceName,
    required this.status,
    required this.namespace,
    this.encryptedAPKAMSymmetricKey,
  });

  factory EnrollmentServerResponse.fromServer(MapEntry<String, dynamic> entry) {
    // Example id: a7d6a9.....40a15.new.enrollments.__manage@alice
    // Only interested in the first part.
    final enrollmentId = entry.key.split('.').first;
    return EnrollmentServerResponse(
      enrollmentId: enrollmentId,
      appName: entry.value['appName'] as String,
      deviceName: entry.value['deviceName'] as String,
      // Status can be null when received from a notification
      status: entry.value['status'] != null
          ? getEnrollStatusFromString(entry.value['status'] as String)
          : EnrollmentStatus.pending,
      encryptedAPKAMSymmetricKey:
          entry.value['encryptedAPKAMSymmetricKey'] as String?,
      // Looks like: `namespace: {ns1: rw, ns2: r}`
      namespace: (entry.value['namespace'] as Map<String, dynamic>)
          .cast<String, String>()
          .entries
          .map((e) => NamespacePermission(
                namespace: e.key,
                read: e.value.contains('r'),
                write: e.value.contains('w'),
              ))
          .toList(),
    );
  }
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
