import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

void main() {
  List atSignList = ConfigUtil.getYaml()['enrollment']['atsignList'];
  String namespace = TestConstants.namespace;

  for (var currentAtSign in atSignList) {
    test('A test to tear down the enrollment setup for $currentAtSign',
        () async {
      await TestSuiteInitializer.getInstance()
          .testInitializer(currentAtSign, namespace, 'pkam');

      List<Enrollment>? pendingEnrollments = await AtClientManager.getInstance()
          .atClient
          .enrollmentService
          ?.fetchEnrollmentRequests(
              enrollmentListParams: EnrollmentListRequestParam()
                ..enrollmentListFilter = [EnrollmentStatus.pending]);

      // At end of the end-to-end test suite execution, deny all the pending enrollments.
      if (pendingEnrollments != null && pendingEnrollments.isNotEmpty) {
        for (Enrollment enrollment in pendingEnrollments) {
          await AtClientManager.getInstance().atClient.enrollmentService?.deny(
              EnrollmentRequestDecision.denied(enrollment.enrollmentId!));
        }
      }

      List<Enrollment>? approvedEnrollments =
          await AtClientManager.getInstance()
              .atClient
              .enrollmentService
              ?.fetchEnrollmentRequests(
                  enrollmentListParams: EnrollmentListRequestParam()
                    ..enrollmentListFilter = [EnrollmentStatus.approved]);

      // At end of the end-to-end test suite execution, revoke all the approved enrollments.
      if (approvedEnrollments != null && approvedEnrollments.isNotEmpty) {
        for (Enrollment enrollment in approvedEnrollments) {
          await AtClientManager.getInstance()
              .atClient
              .enrollmentService
              ?.revoke(
                  EnrollmentRequestDecision.revoked(enrollment.enrollmentId!));
        }
      }
    });
  }
}
