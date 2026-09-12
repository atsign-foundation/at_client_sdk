import 'dart:async';

import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/enrollment_approver.dart';
import 'package:at_auth/src/enroll/enrollment_handshake.dart';
import 'package:at_auth/src/enroll/enrollment_progress.dart';
import 'package:at_auth/src/enroll/enrollment_submitter.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/approver_key_material.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

/// A concrete implementation of [AtEnrollment] for managing enrollments.
///
/// The work belongs to three collaborators, one per side of an enrollment:
/// [EnrollmentSubmitter] asks, [EnrollmentApprover] decides, and
/// [EnrollmentHandshake] waits out the decision and collects what it released.
/// They share one [EnrollmentProgress] because a caller listens to
/// [progressStream] once, across a submission and the wait that follows it.
///
/// This class holds no enrollment state of its own, and it declares no
/// defaults of its own either: every unstated value comes from the constants
/// on [AtEnrollment], which is where a caller's unstated retry interval or
/// passcode expiry is decided whichever of the two types it holds. The
/// collaborators then take those values explicitly.
class AtEnrollmentImpl implements AtEnrollment {
  AtEnrollmentImpl();

  final EnrollmentProgress _progress = EnrollmentProgress();
  late final EnrollmentApprover _approver = EnrollmentApprover();
  late final EnrollmentSubmitter _submitter =
      EnrollmentSubmitter(_progress, _approver);
  late final EnrollmentHandshake _handshake = EnrollmentHandshake(_progress);

  @override
  Stream<ProgressEvent> get progressStream => _progress.stream;

  @override
  Future<AtEnrollmentResponse> submit(
          EnrollmentRequest enrollmentRequest, AtLookUp atLookUp) =>
      _submitter.submit(enrollmentRequest, atLookUp);

  @override
  Future<AtEnrollmentResponse> approve(
          EnrollmentRequestDecision enrollmentRequestDecision,
          AtLookUp atLookUp,
          {required ApproverKeyMaterial approverKeys}) =>
      _approver.approve(enrollmentRequestDecision, atLookUp,
          approverKeys: approverKeys);

  @override
  Future<void> waitForApproval(
    AtEnrollmentResponse enrollmentResponse, {
    Duration retryInterval = AtEnrollment.defaultRetryInterval,
    bool logProgress = AtEnrollment.defaultLogProgress,
    int maxRetries = AtEnrollment.defaultMaxRetries,
    AtLookUp? atLookup,
  }) =>
      _handshake.waitForApproval(
        enrollmentResponse,
        retryInterval: retryInterval,
        logProgress: logProgress,
        maxRetries: maxRetries,
        atLookup: atLookup,
      );
}
