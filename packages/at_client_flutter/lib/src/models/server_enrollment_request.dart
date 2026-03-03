import 'package:at_commons/at_commons.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'namespace_permission.dart';

/// {@template enrollment_request}
/// A model representing an enrollment request.
/// {@endtemplate}
@immutable
class ServerEnrollmentRequest {
  /// {@macro enrollment_request}
  const ServerEnrollmentRequest({
    required this.enrollmentId,
    required this.appName,
    required this.deviceName,
    required this.status,
    required this.namespacePermissions,
    this.encryptedAPKAMSymmetricKey,
  });

  /// The unique identifier for this enrollment request.
  final String enrollmentId;

  /// The name of the app that is requesting access.
  final String appName;

  /// The name of the device that is requesting access.
  final String deviceName;

  /// The current status of the request.
  final EnrollmentStatus status;

  /// The encrypted APKAM symmetric key.
  final String? encryptedAPKAMSymmetricKey;

  /// List of permissions requested by the app and device.
  /// Empty list means no permissions.
  final List<NamespacePermission> namespacePermissions;

  /// Creates an [ServerEnrollmentRequest] object from a server response.
  factory ServerEnrollmentRequest.fromServer(MapEntry<String, dynamic> entry) {
    // Example id: a7d6a9.....40a15.new.enrollments.__manage@alice
    // Only need the first part.
    final enrollmentId = entry.key.split('.').first;
    
    return ServerEnrollmentRequest(
      enrollmentId: enrollmentId,
      appName: entry.value['appName'] as String,
      deviceName: entry.value['deviceName'] as String,

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
        const DeepCollectionEquality()
            .equals(other.namespacePermissions, namespacePermissions);
  }

  @override
  int get hashCode =>
      enrollmentId.hashCode ^
      appName.hashCode ^
      deviceName.hashCode ^
      status.hashCode ^
      namespacePermissions.hashCode ^
      encryptedAPKAMSymmetricKey.hashCode;

  @override
  String toString() {
    return 'ServerEnrollmentRequest(enrollmentId: $enrollmentId, '
    'appName: $appName, '
    'deviceName: $deviceName, '
    'status: $status, '
    'namespaces: $namespacePermissions)';
  }
}

