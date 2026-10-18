import 'dart:convert';

import 'package:at_auth/at_auth.dart' show NamespacePermission;
import 'package:at_client/src/response/at_notification.dart';
import 'package:at_commons/at_commons.dart';

/// Class represents the enrollment details
class Enrollment {
  String? enrollmentId;
  String? appName;
  String? deviceName;

  /// The grants this enrollment holds, `{namespace: access}` — e.g.
  /// `{'buzz': 'rw', '__manage': 'rw'}` — despite the singular name.
  Map<String, dynamic>? namespace;
  String? encryptedAPKAMSymmetricKey;

  /// The approval state the atServer holds for this enrollment.
  ///
  /// Served by `enroll:list` and `enroll:fetch`; a roster read through
  /// `enroll:listns` holds approved enrollments only.
  String? status;

  /// The opaque metadata this enrollment carried on its `enroll:request`,
  /// stored verbatim by the atServer; `metadata.keyPackage` holds the
  /// enrolling app's APKAM-signed X-Wing key package, the target an approver
  /// seals this atSign's secrets to.
  ///
  /// ⚠️ Null on an `enroll:fetch` against an atServer older than
  /// at_secondary_server 3.16.5, which does not project `metadata`;
  /// `enroll:list` and `enroll:listns` return it.
  Map<String, dynamic>? metadata;

  /// The key expiry this enrollment's request asked for, from
  /// `apkamKeysExpiryInMillis`: [Duration.zero] or less when it asked for
  /// none, and null when the atServer did not say, which means unknown.
  ///
  /// Once approved, the term the atServer recorded for it.
  Duration? apkamKeysExpiryDuration;

  /// When the atServer stops serving this record: for a pending request,
  /// when the request lapses, and once approved, when the enrollment
  /// expires. Null when it never does, or when the read did not carry it,
  /// as a notification never does.
  DateTime? expiresAt;

  /// The public half of this enrollment's APKAM authentication keypair, the
  /// client authentication signing key. `enroll:list` serves it to a caller
  /// that may approve, and to an enrollment listing its own record; it is
  /// null in other reads, `enroll:fetch` among them.
  String? apkamPublicKey;

  /// [status] as the atServer's vocabulary, or null when the record carries
  /// none.
  EnrollmentStatus? get enrollmentStatus {
    final status = this.status;
    return status == null ? null : getEnrollStatusFromString(status);
  }

  /// [namespace] as one permission per namespace, `r` and `rw` read as
  /// what they grant.
  List<NamespacePermission> get namespacePermissions => [
        for (final entry in (namespace ?? const {}).entries)
          NamespacePermission(
              namespace: entry.key,
              read: '${entry.value}'.contains('r'),
              write: '${entry.value}'.contains('w')),
      ];

  /// The request a `new.enrollments.__manage` notification announces: its
  /// id is the key's first segment and its record is the value.
  static Enrollment fromNotification(AtNotification notification) =>
      fromJSON(jsonDecode(notification.value!) as Map<String, dynamic>)
        ..enrollmentId = notification.key.split('.').first
        ..status ??= EnrollmentStatus.pending.name;

  static Enrollment fromJSON(Map<String, dynamic> json) {
    return Enrollment()
      ..appName = json['appName']
      ..deviceName = json['deviceName']
      ..namespace = json['namespace']
      ..encryptedAPKAMSymmetricKey = json['encryptedAPKAMSymmetricKey']
      ..status = json['status']
      ..metadata = json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : null
      ..apkamKeysExpiryDuration = json['apkamKeysExpiryInMillis'] is int
          ? Duration(milliseconds: json['apkamKeysExpiryInMillis'] as int)
          : null
      ..expiresAt = json['expiresAt'] is String
          ? DateTime.tryParse(json['expiresAt'] as String)?.toUtc()
          : null
      ..apkamPublicKey = json['apkamPublicKey'] is String
          ? json['apkamPublicKey'] as String
          : null;
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = {};

    map['appName'] = appName;
    map['deviceName'] = deviceName;
    map['namespace'] = namespace;
    map['encryptedAPKAMSymmetricKey'] = encryptedAPKAMSymmetricKey;
    map['status'] = status;
    if (metadata != null) map['metadata'] = metadata;
    if (apkamKeysExpiryDuration != null) {
      map['apkamKeysExpiryInMillis'] = apkamKeysExpiryDuration!.inMilliseconds;
    }
    if (expiresAt != null) map['expiresAt'] = expiresAt!.toIso8601String();
    if (apkamPublicKey != null) map['apkamPublicKey'] = apkamPublicKey;

    return map;
  }

  @override
  String toString() {
    return 'enrollmentId: $enrollmentId, appName: $appName, deviceName: $deviceName';
  }
}
