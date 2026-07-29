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

  /// The session this enrollment operation belongs to — the atsign it concerns,
  /// how to reach that atServer, and the [AtAuthSession.atKeysIo] its keys are
  /// read from or written to.
  ///
  /// On the requesting-app path this is replaced during
  /// `AtEnrollment.waitForApproval` with a session carrying the approved
  /// [enrollmentId] and the authenticated connection — pass that straight into
  /// `AtClientManager.fromAuthSession(...)`.
  AtAuthSession session;

  /// Creates an instance of [AtEnrollmentResponse].
  ///
  /// The [enrollmentId] is the unique identifier for the enrollment.
  /// The [enrollStatus] represents the status of the enrollment operation.
  /// The [session] is the session the operation was performed under.
  AtEnrollmentResponse(this.enrollmentId, this.enrollStatus,
      {required this.session});

  @override
  String toString() {
    return 'AtEnrollmentResponse{enrollmentId: $enrollmentId, enrollStatus: $enrollStatus}';
  }

  /// Serializes only the wire-safe identity of the enrollment: [enrollmentId],
  /// [enrollStatus] and the session's atsign.
  ///
  /// [session] itself cannot round-trip — it holds a live [AtKeysIo] and,
  /// after approval, an open connection. [fromJson] therefore takes the session
  /// from the caller rather than reconstructing one.
  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'enrollStatus': enrollStatus.name,
      'atsign': session.atsign,
    };
  }

  /// Rehydrates a response from [toJson] output. [session] must be supplied by
  /// the caller — see [toJson] for why it is not in the json.
  factory AtEnrollmentResponse.fromJson(Map<String, dynamic> json,
      {required AtAuthSession session}) {
    String enrollmentId = json['enrollmentId'];
    EnrollmentStatus enrollmentStatus = EnrollmentStatus.values
        .firstWhere((es) => es.name == json['enrollStatus']);

    return AtEnrollmentResponse(
      enrollmentId,
      enrollmentStatus,
      session: session,
    );
  }
}

/// The result of submitting an [AtEnrollmentRequest]: the server's verdict plus
/// the key material that `AtEnrollment.waitForApproval` needs to finish the
/// handshake.
///
/// [keys] holds only what `submit` could mint locally — the APKAM keypair and
/// the APKAM symmetric key. The rest (the default encryption private key and
/// the self encryption key) exists on the atServer, encrypted under that
/// symmetric key, and is fetched and merged in by `waitForApproval`, which then
/// persists the completed set through [session]'s `atKeysIo`.
///
/// Until then the keyset is deliberately **not** persistable: it has no
/// `defaultSelfEncryptionKey`, which `FileAtKeysIo` requires in order to
/// self-encrypt the APKAM fields at rest. That is why the keys travel on this
/// object rather than through the keystore.
class PendingEnrollment extends AtEnrollmentResponse {
  /// The APKAM keypair and symmetric key minted by `submit`, completed in place
  /// by `waitForApproval`.
  final AtKeys keys;

  PendingEnrollment(
    super.enrollmentId,
    super.enrollStatus, {
    required super.session,
    required this.keys,
  });

  @override
  String toString() {
    return 'PendingEnrollment{enrollmentId: $enrollmentId, '
        'enrollStatus: $enrollStatus}';
  }
}
