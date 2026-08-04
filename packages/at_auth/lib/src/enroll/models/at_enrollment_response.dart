import 'package:at_auth/at_auth.dart';
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

  /// Creates an instance of [AtEnrollmentResponse].
  ///
  /// The [enrollmentId] is the unique identifier for the enrollment.
  /// The [enrollStatus] represents the status of the enrollment operation.
  AtEnrollmentResponse(
    this.enrollmentId,
    this.enrollStatus,
  );

  @override
  String toString() {
    return 'AtEnrollmentResponse{enrollmentId: $enrollmentId, enrollStatus: $enrollStatus}';
  }

  /// Serializes the wire-safe identity of the enrollment: [enrollmentId] and
  /// [enrollStatus]. Key material never appears here — see [PendingEnrollment],
  /// which carries it in memory precisely because it must not be serialized.
  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'enrollStatus': enrollStatus.name,
    };
  }

  /// Rehydrates a response from [toJson] output.
  factory AtEnrollmentResponse.fromJson(Map<String, dynamic> json) {
    String enrollmentId = json['enrollmentId'];
    EnrollmentStatus enrollmentStatus = EnrollmentStatus.values
        .firstWhere((es) => es.name == json['enrollStatus']);

    return AtEnrollmentResponse(
      enrollmentId,
      enrollmentStatus,
    );
  }
}

/// The result of submitting an [AtEnrollmentRequest]: the server's verdict plus
/// the key material that `AtEnrollment.waitForApproval` needs to finish the
/// handshake.
///
/// [atKeys] holds only what `submit` could mint locally — the APKAM keypair and
/// the APKAM symmetric key. The rest (the default encryption private key and
/// the self encryption key) exists on the atServer, encrypted under that
/// symmetric key, and is fetched and merged in by `waitForApproval`, which then
/// persists the completed set through the `AtKeysIo` it is given.
///
/// Until then the keyset is deliberately **not** persistable: it has no
/// `defaultSelfEncryptionKey`, which `FileAtKeysIo` requires in order to
/// self-encrypt the APKAM fields at rest. That is why the keys travel on this
/// object rather than through the keystore.
class PendingEnrollment extends AtEnrollmentResponse {
  /// The APKAM keypair and symmetric key minted by `submit`, completed in place
  /// by `waitForApproval`.
  final AtKeys atKeys;

  PendingEnrollment(
    super.enrollmentId,
    super.enrollStatus, {
    required this.atKeys,
  });

  @override
  String toString() {
    return 'PendingEnrollment{enrollmentId: $enrollmentId, '
        'enrollStatus: $enrollStatus}';
  }
}
