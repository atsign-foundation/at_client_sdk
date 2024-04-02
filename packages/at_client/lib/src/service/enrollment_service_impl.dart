import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';

class EnrollmentServiceImpl implements EnrollmentService {
  final AtClient _atClient;
  final AtEnrollmentBase _atEnrollmentImpl;

  EnrollmentServiceImpl(this._atClient, this._atEnrollmentImpl);

  @override
  Future<List<PendingEnrollmentRequest>> fetchEnrollmentRequests(
      {EnrollListRequestParam? enrollmentListRequest}) async {
    // enrollmentListRequestParams for now is not  used
    // A server side enhancement request is created. https://github.com/atsign-foundation/at_server/issues/1748
    // On implementation of this enhancement/feature, the enrollListRequestParam object can be made use of
    EnrollVerbBuilder enrollBuilder = EnrollVerbBuilder()
      ..operation = EnrollOperationEnum.list
      ..appName = enrollmentListRequest?.appName
      ..deviceName = enrollmentListRequest?.deviceName;

    var response = await _atClient
        .getRemoteSecondary()
        ?.executeCommand(enrollBuilder.buildCommand(), auth: true);

    return _formatEnrollListResponse(response);
  }

  String extractEnrollmentId(String enrollmentKey) {
    return enrollmentKey.split('.')[0];
  }

  List<PendingEnrollmentRequest> _formatEnrollListResponse(response) {
    response = response?.replaceFirst('data:', '');
    Map<String, dynamic> enrollRequests = jsonDecode(response!);
    List<PendingEnrollmentRequest> enrollRequestsFormatted = [];
    for (MapEntry enrollmentRequest in enrollRequests.entries) {
      PendingEnrollmentRequest enrollmentRequestResponse =
          PendingEnrollmentRequest.fromJSON(enrollmentRequest.value);
      enrollmentRequestResponse.enrollmentId =
          extractEnrollmentId(enrollmentRequest.key);
      enrollRequestsFormatted.add(enrollmentRequestResponse);
    }
    return enrollRequestsFormatted;
  }

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.approve(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }

  @override
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.deny(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }
}
