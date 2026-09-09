/// Class represents the enrollment details
class Enrollment {
  String? enrollmentId;
  String? appName;
  String? deviceName;

  /// Singular in name, but it holds the whole grants **map** —
  /// `{namespace: access}`, e.g. `{'buzz': 'rw', '__manage': 'rw'}`.
  Map<String, dynamic>? namespace;
  String? encryptedAPKAMSymmetricKey;

  /// The approval state the atServer holds for this enrollment.
  ///
  /// Served by `enroll:list` and by `enroll:fetch`. A roster read through
  /// `enroll:listns` holds approved enrollments only, so a member read from
  /// there tells a caller nothing this field adds.
  String? status;

  /// The opaque metadata this enrollment carried on its `enroll:request`,
  /// stored verbatim by the atServer.
  ///
  /// ⚠️ **Null on an `enroll:fetch` result from an atServer older than
  /// at_secondary_server 3.16.5**, which added `metadata` to that verb's
  /// projection; before it a fetch answered with `appName`, `deviceName`,
  /// `namespace`, `encryptedAPKAMSymmetricKey` and `status` alone, so reading a
  /// key package off one got null. It comes back from `enroll:list`, which
  /// returns the record whole, and from `enroll:listns`, which returns it for
  /// every approved enrollment in a namespace.
  ///
  /// `metadata.keyPackage` is the enrolling app's APKAM-signed X-Wing key
  /// package — the target an approver seals this atSign's secrets to. It is
  /// only ever written by the request that creates the enrollment record, so
  /// this is where an approver reads it from: it is already in hand by the
  /// time there is anything to approve, and needs no separate lookup.
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
