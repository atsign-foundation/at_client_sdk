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

  static Enrollment fromJSON(Map<String, dynamic> json) {
    return Enrollment()
      ..appName = json['appName']
      ..deviceName = json['deviceName']
      ..namespace = json['namespace']
      ..encryptedAPKAMSymmetricKey = json['encryptedAPKAMSymmetricKey']
      ..status = json['status']
      ..metadata = json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
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

    return map;
  }

  @override
  String toString() {
    return 'enrollmentId: $enrollmentId, appName: $appName, deviceName: $deviceName';
  }
}
