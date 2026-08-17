/// Class represents the enrollment details
class Enrollment {
  String? enrollmentId;
  String? appName;
  String? deviceName;

  /// Singular in name, but it holds the whole grants **map** —
  /// `{namespace: access}`, e.g. `{'buzz': 'rw', '__manage': 'rw'}`.
  Map<String, dynamic>? namespace;
  String? encryptedAPKAMSymmetricKey;

  /// The opaque metadata this enrollment carried on its `enroll:request`,
  /// stored verbatim by the atServer.
  ///
  /// ⚠️ **Null on an `enroll:fetch` result.** That verb returns exactly
  /// `appName`, `deviceName`, `namespace`, `encryptedAPKAMSymmetricKey` and
  /// `status`; it does not carry the metadata, so reading a key package off a
  /// fetch gets null. It comes back from `enroll:list`, which returns the
  /// record whole, and from `enroll:listns`, which returns it for every
  /// approved enrollment in a namespace.
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
    if (metadata != null) map['metadata'] = metadata;

    return map;
  }

  @override
  String toString() {
    return 'enrollmentId: $enrollmentId, appName: $appName, deviceName: $deviceName';
  }
}
