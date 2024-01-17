import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart';

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

  String toJson() {
    Map jsonMap = HashMap();
    jsonMap['enrollmentKey'] = enrollmentKey;
    jsonMap['appName'] = appName;
    jsonMap['deviceName'] = deviceName;
    jsonMap['namespace'] = jsonEncode(namespace);

    return jsonEncode(jsonMap);
  }

  static EnrollmentRequest fromJson(Map<String, dynamic> json,
      {bool jsonIncludesKey = true, String? enrollmentKey}) {
    EnrollmentRequest enrollmentRequest = EnrollmentRequest();
    if (jsonIncludesKey) {
      enrollmentRequest.enrollmentKey = json['enrollmentKey'];
    } else if (!jsonIncludesKey && enrollmentKey != null) {
      enrollmentRequest.enrollmentKey = enrollmentKey;
    } else {
      throw IllegalArgumentException('enrollment key not set');
    }
    return enrollmentRequest
      ..appName = json['appName']
      ..deviceName = json['deviceName']
      ..namespace = json['namespace'];
  }

  static String extractEnrollmentId(String enrollmentKey) {
    return enrollmentKey.split('.')[0];
  }
}
