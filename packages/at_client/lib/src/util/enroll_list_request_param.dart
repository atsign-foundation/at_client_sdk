import 'package:at_client/at_client.dart';

/// class to store request parameters while fetching a list of enrollments
class EnrollmentListRequestParam {
  String? appName;
  String? deviceName;
  String? namespace;

  /// Allows filtering of enroll requests while listing them
  ///
  /// Accepts a [List<EnrollmentStatus>] defaults to all [EnrollmentStatus] values
  List<EnrollmentStatus> enrollmentListFilter = EnrollmentStatus.values;
}
