/// Class represents the enrollment details
class Enrollment {
  String? enrollmentId;
  String? appName;
  String? deviceName;
  Map<String, dynamic>? namespace;
  String? encryptedAPKAMSymmetricKey;

  static Enrollment fromJSON(Map<String, dynamic> json) {
    return Enrollment()
      ..appName = json['appName']
      ..deviceName = json['deviceName']
      ..namespace = json['namespace']
      ..encryptedAPKAMSymmetricKey = json['encryptedAPKAMSymmetricKey'];
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = {};

    map['appName'] = appName;
    map['deviceName'] = deviceName;
    map['namespace'] = namespace;
    map['encryptedAPKAMSymmetricKey'] = encryptedAPKAMSymmetricKey;

    return map;
  }

  @override
  String toString() {
    return 'enrollmentId: $enrollmentId, appName: $appName, deviceName: $deviceName';
  }
}
