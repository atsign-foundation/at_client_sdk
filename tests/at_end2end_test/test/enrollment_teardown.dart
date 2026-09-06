import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

/// Whether [enrollment] is the atSign's root access: read-write on every
/// namespace AND on `__manage`.
///
/// Mirrors the atServer's own rule. Write access to `*` alone does not
/// qualify, and neither does `__manage` alone. The enrollments this suite
/// creates are namespace-scoped, so none of them is a root.
bool isRootEnrollment(Enrollment enrollment) {
  final namespaces = enrollment.namespace ?? const <String, dynamic>{};
  bool writable(Object? access) => access is String && access.contains('w');
  return writable(namespaces[EnrollmentConstants.allNamespaces]) &&
      writable(namespaces[EnrollmentConstants.enrollManageNamespace]);
}

void main() {
  List atSignList = ConfigUtil.getYaml()['enrollment']['atsignList'];
  String namespace = TestConstants.namespace;

  // What went wrong, so tearDownAll can exit non-zero. This file is run with
  // `dart run`, not the test runner, and the exit() below is what the CI step
  // reads -- so without this every failure here was reported as success.
  List<String> failures = [];

  for (var currentAtSign in atSignList) {
    test('A test to tear down the enrollment setup for $currentAtSign',
        () async {
      try {
        await TestSuiteInitializer.getInstance().testInitializer(
            currentAtSign, namespace, 'pkam',
            enableInitialSync: false);

        List<Enrollment>? pendingEnrollments =
            await AtClientManager.getInstance()
                .atClient
                .enrollmentService
                ?.fetchEnrollmentRequests(
                    enrollmentListParams: EnrollmentListRequestParam()
                      ..enrollmentListFilter = [EnrollmentStatus.pending]);

        // At end of the end-to-end test suite execution, deny all the pending enrollments.
        if (pendingEnrollments != null && pendingEnrollments.isNotEmpty) {
          for (Enrollment enrollment in pendingEnrollments) {
            print('Denying the enrollment permission for id: $enrollment');
            await AtClientManager.getInstance()
                .atClient
                .enrollmentService
                ?.deny(EnrollmentRequestDecision.denied(
                    enrollment.enrollmentId!, currentAtSign));
          }
        }

        List<Enrollment>? approvedEnrollments =
            await AtClientManager.getInstance()
                .atClient
                .enrollmentService
                ?.fetchEnrollmentRequests(
                    enrollmentListParams: EnrollmentListRequestParam()
                      ..enrollmentListFilter = [EnrollmentStatus.approved]);

        // At end of the end-to-end test suite execution, revoke all the approved
        // enrollments -- except the atSign's root access, which is not this
        // suite's to remove. The atServer refuses a revoke that would leave no
        // permanent fully privileged enrollment behind, because the atSign would
        // then be unable to approve a replacement once the rest expire. `force`
        // does not waive that; it waives only the rule against revoking the
        // enrollment the caller is itself authenticated as.
        if (approvedEnrollments != null && approvedEnrollments.isNotEmpty) {
          for (Enrollment enrollment in approvedEnrollments) {
            if (isRootEnrollment(enrollment)) {
              print('Leaving the root enrollment in place: $enrollment');
              continue;
            }
            print('Revoking the enrollment permission for id: $enrollment');
            await AtClientManager.getInstance()
                .atClient
                .enrollmentService
                ?.revoke(EnrollmentRequestDecision.revoked(
                    enrollment.enrollmentId!, currentAtSign,
                    force: true));
          }
        }
      } catch (e) {
        failures.add('$currentAtSign: $e');
        rethrow;
      }
    });
  }

  tearDownAll(() async {
    AtClientManager.getInstance().removeAllChangeListeners();
    AtClientManager.getInstance()
        .atClient
        .notificationService
        .stopAllSubscriptions();
    await AtClientManager.getInstance().atClient.stopCompactionJob();
    // Forced, because the e2e client leaves the isolate alive; the code has to
    // reflect the run or the CI step passes no matter what happened.
    if (failures.isNotEmpty) {
      print('Enrollment teardown FAILED for ${failures.length} atSign(s):');
      for (final failure in failures) {
        print('  $failure');
      }
    }
    exit(failures.isEmpty ? 0 : 1);
  });
}
