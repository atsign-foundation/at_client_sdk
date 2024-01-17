import 'dart:collection';
import 'dart:convert';

class EnrollmentRequest {
  late String enrollmentKey;
  late String appName;
  late String deviceName;
  late Map<String, dynamic> namespace;

  String get enrollmentId {
    return extractEnrollmentId(enrollmentKey);
  }

  @override
  String toString() {
    return 'Enrollment Request: enrollmentKey: $enrollmentKey | appName: $appName | deviceName: $deviceName | namespace: ${namespace.toString()}';
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> jsonMap = HashMap();
    jsonMap['enrollmentKey'] = enrollmentKey;
    jsonMap['appName'] = appName;
    jsonMap['deviceName'] = deviceName;
    jsonMap['namespace'] = jsonEncode(namespace);

    return jsonMap;
  }

  static EnrollmentRequest fromJson(Map<String, dynamic> json) {
    EnrollmentRequest enrollmentRequest = EnrollmentRequest();
    return enrollmentRequest
      ..appName = json['appName']
      ..deviceName = json['deviceName']
      ..namespace = json['namespace'];
  }

  static String extractEnrollmentId(String enrollmentKey) {
    return enrollmentKey.split('.')[0];
  }
}
