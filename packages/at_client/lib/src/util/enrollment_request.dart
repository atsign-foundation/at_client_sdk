class EnrollmentRequest {
  late String enrollmentKey;
  late String appName;
  late String deviceName;
  late Map<String, dynamic> namespace;

  @override
  String toString() {
    return 'Enrollment Request: enrollmentKey: $enrollmentKey | appName: $appName | deviceName: $deviceName | namespace: ${namespace.toString()}';
  }
}
