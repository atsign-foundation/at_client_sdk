import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_commons/at_commons.dart';

abstract class AtEnrollmentService {
  Future<EnrollResponse> enroll(EnrollRequest atEnrollmentRequest);
}
