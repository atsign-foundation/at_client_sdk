import 'package:at_client/at_client.dart';

/// class to store request parameters while fetching a list of enrollments
class EnrollListRequestParam {
  String? appName;
  String? deviceName;
  String? namespace;
  List<EnrollmentStatus>? enrollmentListFilter;
}
