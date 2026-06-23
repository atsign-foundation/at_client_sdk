import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/at_keys_legacy.dart';
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart';

/// Base class for enrollment-related data objects.
///
/// Provides a unified interface for accessing [enrollmentId] and
/// [enrollmentStatus] across both server-side enrollment details
/// ([ServerEnrollmentRequest]) and enrollment operation results
/// ([AtEnrollmentResponse]).
abstract class AtEnrollmentRecord {
  String get enrollmentId;
  EnrollmentStatus get enrollmentStatus;
}

/// Backward compatibility for [AtEnrollmentRecord]
typedef EnrollmentBase = AtEnrollmentRecord;

/// Holds details of an enrollment request received from the server.
///
/// The server notifies the approving app when a requesting app submits
/// an enrollment, seeking approval or denial.
@immutable
class ServerEnrollmentRequest extends AtEnrollmentRecord {
  @override
  final String enrollmentId;
  final String appName;
  final String deviceName;
  final EnrollmentStatus status;
  final List<NamespacePermission> namespacePermissions;
  final String? encryptedAPKAMSymmetricKey;

  @override
  EnrollmentStatus get enrollmentStatus => status;

  /// Backwards-compatible alias for [namespacePermissions].
  List<NamespacePermission> get namespace => namespacePermissions;

  ServerEnrollmentRequest({
    required this.enrollmentId,
    required this.appName,
    required this.deviceName,
    required this.status,
    required this.namespacePermissions,
    this.encryptedAPKAMSymmetricKey,
  });

  factory ServerEnrollmentRequest.fromServer(MapEntry<String, dynamic> entry) {
    // Example id: a7d6a9.....40a15.new.enrollments.__manage@alice
    // Only interested in the first part.
    final enrollmentId = entry.key.split('.').first;
    return ServerEnrollmentRequest(
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
      namespacePermissions: (entry.value['namespace'] as Map<String, dynamic>)
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ServerEnrollmentRequest &&
        other.enrollmentId == enrollmentId &&
        other.appName == appName &&
        other.deviceName == deviceName &&
        other.status == status &&
        other.encryptedAPKAMSymmetricKey == encryptedAPKAMSymmetricKey &&
        _listEquals(other.namespacePermissions, namespacePermissions);
  }

  @override
  int get hashCode =>
      enrollmentId.hashCode ^
      appName.hashCode ^
      deviceName.hashCode ^
      status.hashCode ^
      encryptedAPKAMSymmetricKey.hashCode ^
      namespacePermissions.hashCode;

  @override
  String toString() {
    return 'ServerEnrollmentRequest(enrollmentId: $enrollmentId, '
        'appName: $appName, '
        'deviceName: $deviceName, '
        'status: $status, '
        'namespacePermissions: $namespacePermissions)';
  }
}

/// Backwards-compatible alias for [ServerEnrollmentRequest].
typedef EnrollmentServerResponse = ServerEnrollmentRequest;

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Represents the response of an enrollment operation received
/// from the secondary server.
class AtEnrollmentResponse extends AtEnrollmentRecord {
  /// The unique identifier associated with the enrollment.
  @override
  String enrollmentId;

  /// The status of the enrollment operation.
  EnrollmentStatus enrollStatus;

  @override
  EnrollmentStatus get enrollmentStatus => enrollStatus;

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

  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'enrollStatus': enrollStatus.name,
      if (atSign != null) 'atSign': atSign,
    };
  }

  factory AtEnrollmentResponse.fromJson(Map<String, dynamic> json) {
    String enrollmentId = json['enrollmentId'];
    EnrollmentStatus enrollmentStatus = EnrollmentStatus.values
        .firstWhere((es) => es.name == json['enrollStatus']);
    String? atSign = json['atSign'];

    return AtEnrollmentResponse(enrollmentId, enrollmentStatus, atSign: atSign);
  }
}
